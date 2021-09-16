/*
 * This file is part of budgie-desktop
 *
 * Copyright © 2015-2021 Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */


public static int main(string[] args) {
#if HAVE_MUTTER_9
	Budgie.BudgieWM.old_args = args;

	Meta.Context ctx = Meta.create_context("Mutter(Budgie)");
	try {
		if (!ctx.configure_args(ref args)) {
			return Meta.ExitCode.ERROR;
		}
	} catch (GLib.Error e) {
		message("Configuration failed: %s", e.message);
		return Meta.ExitCode.ERROR;
	}

	/* Set plugin type here */
	ctx.set_plugin_gtype(typeof(Budgie.BudgieWM));
	ctx.set_gnome_wm_keybindings("Mutter,GNOME Shell");

	Environment.set_variable("NO_GAIL", "1", true);
	Environment.set_variable("NO_AT_BRIDGE", "1", true);

	try {
		ctx.setup();
		ctx.start();
		ctx.notify_ready();
		ctx.run_main_loop();
	} catch (GLib.Error e) {
		message("Error running WM: %s", e.message);
	}
	return Meta.ExitCode.SUCCESS;
#else
	unowned OptionContext? ctx = null;
	Budgie.BudgieWM.old_args = args;

	ctx = Meta.get_option_context();

	try {
		if (!ctx.parse(ref args)) {
			return Meta.ExitCode.ERROR;
		}
	} catch (OptionError e) {
		message("Unknown option: %s", e.message);
		return Meta.ExitCode.ERROR;
	}

	/* Set plugin type here */
	Meta.Plugin.manager_set_plugin_type(typeof(Budgie.BudgieWM));
	Meta.set_gnome_wm_keybindings("Mutter,GNOME Shell");
	Meta.set_wm_name("Mutter(Budgie)");

	Environment.set_variable("NO_GAIL", "1", true);
	Environment.set_variable("NO_AT_BRIDGE", "1", true);

	Meta.init();

	Meta.register_with_session();

	return Meta.run();
#endif
}
