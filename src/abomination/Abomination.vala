/*
 * This file is part of budgie-desktop
 *
 * Copyright © 2018-2021 Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

private const string RAVEN_DBUS_NAME = "org.budgie_desktop.Raven";
private const string RAVEN_DBUS_OBJECT_PATH = "/org/budgie_desktop/Raven";

[DBus (name="org.budgie_desktop.Raven")]
public interface AbominationRavenRemote : GLib.Object {
	public async abstract void SetPauseNotifications(bool paused) throws DBusError, IOError;
}

namespace Budgie {
	/**
	 * Abomination is our application state tracking manager
	 */
	public class Abomination : GLib.Object {
		private Budgie.AppSystem? app_system = null;
		private Settings? color_settings = null;
		private Settings? wm_settings = null;
		private bool original_night_light_setting = false;
		private bool should_disable_night_light_on_fullscreen = false;
		private bool should_pause_notifications_on_fullscreen = false;

		private HashTable<ulong?,Wnck.Window?> fullscreen_windows; // fullscreen_windows is a list of fullscreen windows based on their X window ID and respective Wnck.Window
		private HashTable<ulong?, unowned AbominationRunningApp?> running_apps_id; // running_apps_ids is a list of apps based on the window id and AbominationRunningApp
		private HashTable<string?, unowned AbominationAppGroup?> running_app_groups; // running_app_groups is a list of app groups based on the group name

		private Wnck.Screen screen = null;
		private AbominationRavenRemote? raven_proxy = null;

		private ulong color_id = 0;

		/**
		 * Signals
		 */
		public signal void added_app(string group, AbominationRunningApp app);
		public signal void removed_app(string group, AbominationRunningApp app);
		public signal void updated_group(AbominationAppGroup group);

		public Abomination() {
			this.app_system = new Budgie.AppSystem();
			this.color_settings = new Settings("org.gnome.settings-daemon.plugins.color");
			this.wm_settings = new Settings("com.solus-project.budgie-wm");

			this.fullscreen_windows = new HashTable<ulong?,Wnck.Window?>(int_hash, str_equal);
			this.running_apps_id = new HashTable<ulong?, unowned AbominationRunningApp?>(int_hash, int_equal);
			this.running_app_groups = new HashTable<string?, unowned AbominationAppGroup?>(str_hash, str_equal);

			this.screen = Wnck.Screen.get_default();

			Bus.get_proxy.begin<AbominationRavenRemote>(BusType.SESSION, RAVEN_DBUS_NAME, RAVEN_DBUS_OBJECT_PATH, 0, null, on_raven_get);

			if (this.color_settings != null) { // gsd colors plugin schema defined
				this.update_night_light_value();
				this.color_id = color_settings.changed["night-light-enabled"].connect(update_night_light_value);
			}

			if (this.wm_settings != null) {
				this.update_should_disable_night_light();
				this.update_should_pause_notifications();

				this.wm_settings.changed["disable-night-light-on-fullscreen"].connect(update_should_disable_night_light);
				this.wm_settings.changed["pause-notifications-on-fullscreen"].connect(update_should_pause_notifications);
			}

			this.screen.window_opened.connect(this.add_app);
			this.screen.window_closed.connect(this.remove_app);

			screen.get_windows().foreach((window) => { // Init all our current running windows
				add_app(window);
			});
		}

		/* Hold onto our Raven proxy ref */
		public void on_raven_get(Object? o, AsyncResult? res) {
			try {
				raven_proxy = Bus.get_proxy.end(res);
			} catch (Error e) {
				warning("Failed to gain Raven proxy: %s", e.message);
			}
		}

		/**
		 * is_disallowed_window_type will check if this specified window is a disallowed type
		 */
		public bool is_disallowed_window_type(Wnck.Window window) {
			Wnck.WindowType win_type = window.get_window_type(); // Get the window type

			return (win_type == Wnck.WindowType.DESKTOP) || // Desktop-mode (like Nautilus' Desktop Icons)
				   (win_type == Wnck.WindowType.DIALOG) || // Dialogs
				   (win_type == Wnck.WindowType.DOCK) || // Like Budgie Panel
				   (win_type == Wnck.WindowType.SPLASHSCREEN) || // Splash screens
				   (win_type == Wnck.WindowType.UTILITY); // Utility like a control on an emulator
		}

		public AbominationRunningApp? get_app_from_window_id(ulong window_id) {
			return this.running_apps_id.get(window_id);
		}

		public List<weak AbominationRunningApp> get_running_apps() {
			return this.running_apps_id.get_values();
		}

		/**
		 * Get the first running app of an app group identified by its name.
		 */
		public AbominationRunningApp? get_first_app_of_group(string group) {
			AbominationAppGroup app_group = this.running_app_groups.get(group);
			if (app_group == null) {
				return null;
			}

			Wnck.Window window = app_group.get_windows().nth_data(0);
			if (window == null) {
				return null;
			}

			Budgie.AbominationRunningApp first_app = this.running_apps_id.get(window.get_xid());
			if (first_app == null) {
				return null;
			}

			if ((first_app.get_window() != null) && (first_app.get_window().get_state() == Wnck.WindowState.SKIP_TASKLIST)) {
				return null;
			}

			return first_app;
		}

		private AbominationAppGroup? get_window_group(Wnck.Window window) {
			string group_name = get_group_name(window);
			if (!this.running_app_groups.contains(group_name)) {
				return null;
			}
			return this.running_app_groups.get(group_name);
		}

		/**
		 * add_app will add a running application based on the provided window
		 */
		private void add_app(Wnck.Window window) {
			// Could use group name to determine if apps can be grouped together
			// So far, here are the apps without a groupname:
			//  - Android studio emulator (null)
			//  - GTK4 demos (empty string) -> how to make it so that grouping works? (only application class cuz it's another windows with controls)
			//  - LibreOffice (first open null, then open the app, but icon isn't here)
			//  - Chrome with multi profiles (get_class_instance_name is still null...) will have to do an hard check on this one cuz it's impossible otherwise...

			// LibreOffice have different behavior depending on how it was started
			// Test grouping of chrome canary / dev / snap / flatpak too (works)

			if (this.is_disallowed_window_type(window)) { // Disallowed type
				return;
			}

			if (window.is_skip_pager() || window.is_skip_tasklist()) { // Skip pager or tasklist
				return;
			}

			AbominationAppGroup group = this.get_window_group(window);
			if (group == null) {
				group = new AbominationAppGroup(window);
				this.running_app_groups.insert(group.get_name(), group);

				group.renamed_group.connect((new_group_name, old_group_name) => {
					this.rename_group(old_group_name, new_group_name); // Rename the class
				});
			}

			AbominationRunningApp app = new AbominationRunningApp(this.app_system, window, group); // Create an abomination app
			if (app == null || app.get_group_name() == null) { // Shouldn't be the case, fail immediately
				return;
			}

			this.running_apps_id.insert(app.id, app); // Append the app based on id
			this.added_app(app.get_group_name(), app); // notify that the app was added

			group.add_window(window); // Append the window to the group

			this.track_window_fullscreen_state(app.get_window(), app.get_window().get_state());

			app.get_window().state_changed.connect((changed, new_state) => {
				if (Wnck.WindowState.FULLSCREEN in (changed | new_state)) {
					this.track_window_fullscreen_state(app.get_window(), new_state);
				}
			});
		}

		/**
		 * remove_app will remove a running application based on the provided window
		 *
		 * FIXME: sometime closing one instance of a grouped app will remove all (only gnome MPV so far)
		 */
		private void remove_app(Wnck.Window window) {
			AbominationAppGroup group = this.get_window_group(window);
			if (group == null) {
				return;
			}

			group.remove_window(window);

			if (group.get_windows().length() == 0) { // remove empty group
				this.running_app_groups.remove(group.get_name());
				debug("Removed group: %s", group.get_name());
			}

			ulong id = window.get_xid();
			AbominationRunningApp app = this.running_apps_id.get(id); // Get the running app

			this.running_apps_id.steal(id); // Remove from running_apps_id

			this.track_window_fullscreen_state(window, null); // Remove from fullscreen_windows and toggle state if necessary

			// FIXME: app.get_window() is null at this point, but shouldn't be...
			if (app != null) { // App is defined
				this.removed_app(app.get_group_name(), app); // Notify that we called remove
			}
		}

		/**
		 * rename_group will rename any associated group based on the old group name
		 * The old group name is determined by current windows associated with the group
		 */
		private void rename_group(string old_group_name, string new_group_name) {
			// FIXME: Apps are in the same group, yet they are not grouped together - why? (only apply to libre-office)
			// maybe the renaming is causing some issue with icon tasklist?
			// FIXME: libre office is doing shit with the popover, etc, what a shitty app

			AbominationAppGroup group = this.running_app_groups.get(old_group_name);

			this.running_app_groups.remove(old_group_name); // remove old group
			this.running_app_groups.insert(new_group_name, group); // add the new group

			this.updated_group(group); // Should always be invoked last
		}

		/**
		 * Adds and removes windows from fullscreen_windows depending on their state.
		 * Additionally, toggles night light and notification pausing as necessary if either are enabled.
		 */
		private void track_window_fullscreen_state(Wnck.Window window, Wnck.WindowState? state) {
			ulong window_xid = window.get_xid();

			// only add a fullscreen window if it isn't currently minimized
			if (!(window_xid in fullscreen_windows) && state_is_fullscreen(state)) {
				fullscreen_windows.insert(window_xid, window); // Add to fullscreen_windows
			} else if (window_xid in fullscreen_windows) {
				fullscreen_windows.steal(window_xid); // Remove from fullscreen_windows
			}

			toggle_night_light(); // Ensure we toggle Night Light if needed
			set_notifications_paused(); // Ensure we pause notifications if needed
		}

		private bool state_is_fullscreen(Wnck.WindowState? state) {
			return state != null && (
				Wnck.WindowState.FULLSCREEN in state &&
				!(Wnck.WindowState.MINIMIZED in state || Wnck.WindowState.HIDDEN in state)
			);
		}

		/**
		 * toggle_night_light will toggle the state of the night light depending on requested state
		 * If we're disabling, we'll check if there is any items in fullscreen_windows first
		 */
		private void toggle_night_light() {
			if (should_disable_night_light_on_fullscreen) {
				SignalHandler.block(color_settings, color_id);

				if (fullscreen_windows.size() >= 1) { // Has fullscreen windows
					color_settings.set_boolean("night-light-enabled", false);
				} else { // Has no fullscreen windows
					color_settings.set_boolean("night-light-enabled", original_night_light_setting); // Set back to our original
				}

				SignalHandler.unblock(color_settings, color_id);
			}
		}

		private void set_notifications_paused() {
			if (should_pause_notifications_on_fullscreen) {
				raven_proxy.SetPauseNotifications.begin(fullscreen_windows.size() >= 1);
			}
		}

		/**
		 * update_should_disable_night_light will update our value determining if we should disable night light on fullscreen
		 */
		private void update_should_disable_night_light() {
			if (wm_settings != null) {
				should_disable_night_light_on_fullscreen = wm_settings.get_boolean("disable-night-light-on-fullscreen");
			}
		}

		/**
		 * update_should_pause_notifications will update our value determining if we should pause notifications on fullscreen
		 */
		private void update_should_pause_notifications() {
			if (wm_settings != null) {
				should_pause_notifications_on_fullscreen = wm_settings.get_boolean("pause-notifications-on-fullscreen");
			}
		}

		/**
		 * update_night_light_value will update our copy / original night light enabled value
		 */
		private void update_night_light_value() {
			if (color_settings != null) {
				original_night_light_setting = color_settings.get_boolean("night-light-enabled");
			}
		}
	}
}