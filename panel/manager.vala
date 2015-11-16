/*
 * This file is part of arc-desktop
 * 
 * Copyright 2015 Ikey Doherty <ikey@solus-project.com>
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */
 
using LibUUID;

namespace Arc
{

public static const string DBUS_NAME        = "com.solus_project.arc.Panel";
public static const string DBUS_OBJECT_PATH = "/com/solus_project/arc/Panel";

/**
 * Available slots
 */

[Flags]
public enum PanelPosition {
    NONE        = 1 << 0,
    BOTTOM      = 1 << 1,
    TOP         = 1 << 2,
    LEFT        = 1 << 3,
    RIGHT       = 1 << 4
}

[Flags]
public enum AppletPackType {
    START       = 1 << 0,
    END         = 1 << 2
}

[Flags]
public enum AppletAlignment {
    START       = 1 << 0,
    CENTER      = 1 << 1,
    END         = 1 << 2
}

struct Screen {
    PanelPosition slots;
    Gdk.Rectangle area;
}


/** Name of the plugin */
public static const string APPLET_KEY_NAME      = "name";
public static const string APPLET_KEY_ALIGN     = "alignment";
public static const string APPLET_KEY_PACK      = "pack-type";
public static const string APPLET_KEY_POS       = "position";
public static const string APPLET_KEY_PAD_START = "padding-start";
public static const string APPLET_KEY_PAD_END   = "padding-end";

/**
 * Used to track Applets in a sane way
 */
public class AppletInfo : GLib.Object
{

    /** Applet instance */
    public Arc.Applet applet { public get; private set; }

    private unowned GLib.Settings? settings;

    /** Known icon name */
    public string icon {  public get; protected set; }

    /** Instance name */
    public string name { public get; protected set; }

    public string uuid { public get; protected set; }

    /** Packing type */
    public string pack_type { public get ; public set ; default = "start"; }

    /** Whether to place in the status area or not */
    public string alignment { public get ; public set ; default = "start"; }

    /** Start padding */
    public int pad_start { public get ; public set ; default = 0; }

    /** End padding */
    public int pad_end { public get ; public set; default = 0; }

    /** Position (packging index */
    public int position { public get; public set; default = 0; }

    /**
     * Construct a new AppletInfo. Simply a wrapper around applets
     */
    public AppletInfo(Peas.PluginInfo? plugin_info, string uuid, Arc.Applet applet, GLib.Settings settings)
    {
        this.applet = applet;
        icon = plugin_info.get_icon_name();
        this.name = plugin_info.get_name();
        this.uuid = uuid;
        this.settings = settings;
        this.bind_settings();
    }

    void bind_settings()
    {
        settings.bind(Arc.APPLET_KEY_NAME, this, "name", SettingsBindFlags.DEFAULT);
        settings.bind(Arc.APPLET_KEY_POS, this, "position", SettingsBindFlags.DEFAULT);
        settings.bind(Arc.APPLET_KEY_ALIGN, this, "alignment", SettingsBindFlags.DEFAULT);
        settings.bind(Arc.APPLET_KEY_PACK, this, "pack-type", SettingsBindFlags.DEFAULT);
        settings.bind(Arc.APPLET_KEY_PAD_START, this, "pad-start", SettingsBindFlags.DEFAULT);
        settings.bind(Arc.APPLET_KEY_PAD_END, this, "pad-end", SettingsBindFlags.DEFAULT);

        /* Automatically handle margins */
        this.bind_property("pad-start", applet, "margin-start", BindingFlags.DEFAULT);
        this.bind_property("pad-end", applet, "margin-end", BindingFlags.DEFAULT);
    }
}

/**
 * Maximum slots. 4 because that's generally how many sides a rectangle has..
 */
public static const uint MAX_SLOTS         = 4;

/**
 * Root prefix for fixed schema
 */
public static const string ROOT_SCHEMA     = "com.solus-project.arc-panel";

/**
 * Relocatable schema ID for toplevel panels
 */
public static const string TOPLEVEL_SCHEMA = "com.solus-project.arc-panel.panel";

/**
 * Prefix for all relocatable panel settings
 */
public static const string TOPLEVEL_PREFIX = "/com/solus-project/arc-panel/panels";


/**
 * Relocatable schema ID for applets
 */
public static const string APPLET_SCHEMA   = "com.solus-project.arc-panel.applet";

/**
 * Prefix for all relocatable applet settings
 */
public static const string APPLET_PREFIX   = "/com/solus-project/arc-panel/applets";

/**
 * Known panels
 */
public static const string ROOT_KEY_PANELS     = "panels";

/** Panel position */
public static const string PANEL_KEY_POSITION   = "location";

/** Panel applets */
public static const string PANEL_KEY_APPLETS    = "applets";

/** Night mode/dark theme */
public static const string PANEL_KEY_DARK_THEME = "dark-theme";


[DBus (name = "com.solus_project.arc.Panel")]
public class PanelManagerIface
{

    public string get_version()
    {
        return Arc.VERSION;
    }
}

public class PanelManager
{
    private PanelManagerIface? iface;
    bool setup = false;

    HashTable<int,Screen?> screens;
    HashTable<string,Arc.Panel?> panels;

    int primary_monitor = 0;
    Settings settings;
    Peas.Engine engine;
    Peas.ExtensionSet extensions;

    HashTable<string, Peas.PluginInfo?> plugins;

    public PanelManager()
    {
        screens = new HashTable<int,Screen?>(direct_hash, direct_equal);
        panels = new HashTable<string,Arc.Panel?>(str_hash, str_equal);
        plugins = new HashTable<string,Peas.PluginInfo?>(str_hash, str_equal);
    }

    public Arc.AppletInfo? get_applet(string key)
    {
        return null;
    }

    string create_panel_path(string uuid)
    {
        return "%s/{%s}/".printf(Arc.TOPLEVEL_PREFIX, uuid);
    }

    string create_applet_path(string uuid)
    {
        return "%s/{%s}/".printf(Arc.APPLET_PREFIX, uuid);

    }

    /**
     * Discover all possible monitors, and move things accordingly.
     * In future we'll support per-monitor panels, but for now everything
     * must be in one of the edges on the primary monitor
     */
    public void on_monitors_changed()
    {
        var scr = Gdk.Screen.get_default();
        var mon = scr.get_primary_monitor();
        HashTableIter<string,Arc.Panel?> iter;
        unowned string uuid;
        unowned Arc.Panel panel;
        unowned Screen? primary;

        screens.remove_all();

        /* When we eventually get monitor-specific panels we'll find the ones that
         * were left stray and find new homes, or temporarily disable
         * them */
        for (int i = 0; i < scr.get_n_monitors(); i++) {
            Gdk.Rectangle usable_area;
            scr.get_monitor_geometry(i, out usable_area);
            Arc.Screen? screen = Arc.Screen() {
                area = usable_area,
                slots = 0
            };
            screens.insert(i, screen);
        }

        primary = screens.lookup(mon);

        /* Fix all existing panels here */
        iter = HashTableIter<string,Arc.Panel?>(panels);
        while (iter.next(out uuid, out panel)) {
            if (mon != this.primary_monitor) {
                /* Force existing panels to update to new primary display */
                panel.update_geometry(primary.area, panel.position);
            }
            /* Re-take the position */
            primary.slots |= panel.position;
        }
        this.primary_monitor = mon;
    }

    private void on_bus_acquired(DBusConnection conn)
    {
        try {
            iface = new PanelManagerIface();
            conn.register_object(Arc.DBUS_OBJECT_PATH, iface);
        } catch (Error e) {
            stderr.printf("Error registering PanelManager: %s\n", e.message);
            Process.exit(1);
        }
    }

    public void on_name_acquired(DBusConnection conn, string name)
    {
        this.setup = true;
        /* Well, off we go to be a panel manager. */
        do_setup();
    }

    /**
     * Initial setup, once we've owned the dbus name
     * i.e. no risk of dying
     */
    void do_setup()
    {
        var scr = Gdk.Screen.get_default();
        primary_monitor = scr.get_primary_monitor();
        scr.monitors_changed.connect(this.on_monitors_changed);

        /* Set up dark mode across the desktop */
        settings = new GLib.Settings(Arc.ROOT_SCHEMA);
        var gtksettings = Gtk.Settings.get_default();
        this.settings.bind(Arc.PANEL_KEY_DARK_THEME, gtksettings, "gtk-application-prefer-dark-theme", SettingsBindFlags.GET);

        this.on_monitors_changed();

        setup_plugins();

        if (!load_panels()) {
            message("Creating default panel layout");
            create_default();
        } else {
            message("Loaded existing configuration");
        }
    }

    /**
     * Initialise the plugin engine, paths, loaders, etc.
     */
    void setup_plugins()
    {
        engine = Peas.Engine.get_default();
        engine.enable_loader("python3");

        /* Ensure libpeas doesn't freak the hell out for Python extensions */
        try {
            var repo = GI.Repository.get_default();
            repo.require("Peas", "1.0", 0);
            repo.require("PeasGtk", "1.0", 0);
            repo.require("Arc", "1.0", 0);
        } catch (Error e) {
            message("Error loading typelibs: %s", e.message);
        }

        /* System path */
        var dir = Environment.get_user_data_dir();
        engine.add_search_path(Arc.MODULE_DIRECTORY, Arc.MODULE_DATA_DIRECTORY);

        /* User path */
        var hmod = Path.build_path(Path.DIR_SEPARATOR_S, dir, "arc-desktop", "modules");
        var hdata = Path.build_path(Path.DIR_SEPARATOR_S, dir, "arc-desktop", "data");

        engine.add_search_path(hmod, hdata);

        extensions = new Peas.ExtensionSet(engine, typeof(Arc.Plugin));

        extensions.extension_added.connect(on_extension_added);
        engine.load_plugin.connect_after((i)=> {
            Peas.Extension? e = extensions.get_extension(i);
            if (e == null) {
                critical("Failed to find extension for: %s", i.get_name());
                return;
            }
            on_extension_added(i, e);
        });
    }

    /**
     * Indicate that a plugin that was being waited for, is now available
     */
    public signal void extension_loaded(string name);

    /**
     * Handle extension loading
     */
    void on_extension_added(Peas.PluginInfo? info, Object p)
    {
        if (plugins.contains(info.get_name())) {
            return;
        }
        plugins.insert(info.get_name(), info);
        extension_loaded(info.get_name());
    }

    public bool is_extension_loaded(string name)
    {
        return plugins.contains(name);
    }

    /**
     * Determine if the extension is known to be valid
     */
    public bool is_extension_valid(string name)
    {
        if (this.get_plugin_info(name) == null) {
            return false;
        }
        return true;
    }

    /**
     * PeasEngine.get_plugin_info == completely broken
     */
    private unowned Peas.PluginInfo? get_plugin_info(string name)
    {
        foreach (unowned Peas.PluginInfo? info in this.engine.get_plugin_list()) {
            if (info.get_name() == name) {
                return info;
            }
        }
        return null;
    }

    public void modprobe(string name)
    {
        Peas.PluginInfo? i = this.get_plugin_info(name);
        if (i == null) {
            warning("arc_panel_modprobe called for non existent module: %s", name);
            return;
        }
        this.engine.try_load_plugin(i);
    }

    /**
     * Attempt to load plugin, will set the plugin-name on failure
     */
    public Arc.AppletInfo? load_applet_instance(string? uuid, out string name, GLib.Settings? psettings = null)
    {
        var path = this.create_applet_path(uuid);
        GLib.Settings? settings = null;
        if (psettings == null) {
            settings = new Settings.with_path(Arc.APPLET_SCHEMA, path);
        } else {
            settings = psettings;
        }
        var pname = settings.get_string(Arc.APPLET_KEY_NAME);
        Peas.PluginInfo? pinfo = plugins.lookup(pname);

        /* Not yet loaded */
        if (pinfo == null) {
            pinfo = this.get_plugin_info(pname);
            if (pinfo == null) {
                warning("Trying to load invalid plugin: %s %s", pname, uuid);
                name = null;
                return null;
            }
            engine.try_load_plugin(pinfo);
            name = pname;
            return null;
        }
        var extension = extensions.get_extension(pinfo);
        if (extension == null) {
            name = pname;
            return null;
        }
        name = null;
        Arc.Applet applet = (extension as Arc.Plugin).get_panel_widget();
        var info = new Arc.AppletInfo(pinfo, uuid, applet, settings);

        return info;
    }

    /**
     * Attempt to create a fresh applet instance
     */
    public Arc.AppletInfo? create_new_applet(string name, string uuid)
    {
        string? unused = null;
        if (!plugins.contains(name)) {
            return null;
        }
        var path = this.create_applet_path(uuid);
        var settings = new Settings.with_path(Arc.APPLET_SCHEMA, path);
        settings.set_string(Arc.APPLET_KEY_NAME, name);
        return this.load_applet_instance(uuid, out unused, settings);
    }

    /**
     * Find the next available position on the given monitor
     */
    public PanelPosition get_first_position(int monitor)
    {
        if (!screens.contains(monitor)) {
            error("No screen for monitor: %d - This should never happen!", monitor);
            return PanelPosition.NONE;
        }
        Screen? screen = screens.lookup(monitor);

        if ((screen.slots & PanelPosition.TOP) == 0) {
            return PanelPosition.TOP;
        } else if ((screen.slots & PanelPosition.BOTTOM) == 0) {
            return PanelPosition.BOTTOM;
        } else if ((screen.slots & PanelPosition.LEFT) == 0) {
            return PanelPosition.LEFT;
        } else if ((screen.slots & PanelPosition.RIGHT) == 0) {
            return PanelPosition.RIGHT;
        } else {
            return PanelPosition.NONE;
        }
    }

    /**
     * Determine how many slots are available
     */
    public uint slots_available()
    {
        return MAX_SLOTS - panels.size();
    }

    /**
     * Determine how many slots have been used
     */
    public uint slots_used()
    {
        return panels.size();
    }

    /**
     * Load a panel by the given UUID, and optionally configure it
     */
    void load_panel(string uuid, bool configure = false)
    {
        if (panels.contains(uuid)) {
            return;
        }

        string path = this.create_panel_path(uuid);
        PanelPosition position;

        var settings = new GLib.Settings.with_path(Arc.TOPLEVEL_SCHEMA, path);
        Arc.Panel? panel = new Arc.Panel(this, uuid, settings);
        panels.insert(uuid, panel);

        if (!configure) {
            return;
        }

        position = (PanelPosition)settings.get_enum(Arc.PANEL_KEY_POSITION);
        this.show_panel(uuid, position);
    }

    void show_panel(string uuid, PanelPosition position)
    {
        Arc.Panel? panel = panels.lookup(uuid);
        Screen? scr;

        if (panel == null) {
            warning("Asked to show non-existent panel: %s", uuid);
            return;
        }

        scr = screens.lookup(this.primary_monitor);
        if ((scr.slots & position) != 0) {
            scr.slots |= position;
        }
        this.set_placement(uuid, position);
    }

    /**
     * Enforce panel placement
     */
    void set_placement(string uuid, PanelPosition position)
    {
        Arc.Panel? panel = panels.lookup(uuid);
        string? key = null;
        Arc.Panel? val = null;
        Arc.Panel? conflict = null;

        if (panel == null) {
            warning("Trying to move non-existent panel: %s", uuid);
            return;
        }
        Screen? area = screens.lookup(primary_monitor);

        PanelPosition old = panel.position;

        if (old == position) {
            warning("Attempting to move panel to the same position it's already in");
            return;
        }

        /* Attempt to find a conflicting position */
        var iter = HashTableIter<string,Arc.Panel?>(panels);
        while (iter.next(out key, out val)) {
            if (val.position == position) {
                conflict = val;
                break;
            }
        }

        panel.hide();
        if (conflict != null) {
            conflict.hide();
            conflict.update_geometry(area.area, old);
            conflict.show();
        } else {
            area.slots ^= old;
            area.slots |= position;
            panel.update_geometry(area.area, position);
        }

        /* This does mean re-configuration a couple of times that could
         * be avoided, but it's just to ensure proper functioning..
         */
        this.update_screen();
        panel.show();
    }

    /**
     * Force update geometry for all panels
     */
    void update_screen()
    {
        string? key = null;
        Arc.Panel? val = null;
        Screen? area = screens.lookup(primary_monitor);
        var iter = HashTableIter<string,Arc.Panel?>(panels);
        while (iter.next(out key, out val)) {
            val.update_geometry(area.area, val.position);
        }
    }

    /**
     * Load all known panels
     */
    bool load_panels()
    {
        string[] panels = this.settings.get_strv(Arc.ROOT_KEY_PANELS);
        if (panels.length == 0) {
            return false;
        }

        foreach (string uuid in panels) {
            this.load_panel(uuid, true);
        }

        this.update_screen();
        return true;
    }

    void create_panel()
    {
        if (this.slots_available() < 1) {
            warning("Asked to create panel with no slots available");
            return;
        }

        var position = get_first_position(this.primary_monitor);
        if (position == PanelPosition.NONE) {
            critical("No slots available, this should not happen");
            return;
        }

        var uuid = LibUUID.new(UUIDFlags.LOWER_CASE|UUIDFlags.TIME_SAFE_TYPE);
        load_panel(uuid, false);

        set_panels();
        show_panel(uuid, position);
    }

    /**
     * Update our known panels
     */
    void set_panels()
    {
        unowned Arc.Panel? panel;
        unowned string? key;
        string[]? keys = null;

        var iter = HashTableIter<string,Arc.Panel?>(panels);
        while (iter.next(out key, out panel)) {
            keys += key;
        }

        this.settings.set_strv(Arc.ROOT_KEY_PANELS, keys);
    }

    /**
     * Create new default panel layout
     */
    void create_default()
    {
        /* Eventually we'll do something fancy with defaults, when
         * applet loading lands */
        create_panel();
    }

    private void on_name_lost(DBusConnection conn, string name)
    {
        if (setup) {
            message("Replaced existing arc-panel");
        } else {
            message("Another panel is already running. Use --replace to replace it");
        }
        Gtk.main_quit();
    }

    public void serve(bool replace = false)
    {
        var flags = BusNameOwnerFlags.ALLOW_REPLACEMENT;
        if (replace) {
            flags |= BusNameOwnerFlags.REPLACE;
        }
        Bus.own_name(BusType.SESSION, Arc.DBUS_NAME, flags,
            on_bus_acquired, on_name_acquired, on_name_lost);
    }
}

} /* End namespace */
