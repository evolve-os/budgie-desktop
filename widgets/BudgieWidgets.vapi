/* BudgieWidgets.vapi generated by valac 0.26.1, do not modify. */

namespace Budgie {
	[CCode (cheader_filename = "BudgieWidgets.h")]
	public class Animation : GLib.Object {
		public bool can_anim;
		public Budgie.PropChange[] changes;
		public int64 elapsed;
		public uint id;
		public int64 length;
		public bool no_reset;
		public GLib.Object? object;
		public int64 start_time;
		public weak Budgie.TweenFunc tween;
		public weak Gtk.Widget widget;
		public Animation ();
		public void start (Budgie.AnimCompletionFunc? compl);
		public void stop ();
	}
	[CCode (cheader_filename = "BudgieWidgets.h")]
	public class Popover : Gtk.Window {
		public bool passive;
		public Popover (Gtk.Widget? relative_to, bool is_passive = false);
		public override bool button_press_event (Gdk.EventButton event);
		protected void do_grab ();
		public void do_placement ();
		protected void do_tail (Cairo.Context ctx, int x, int y);
		protected void do_ungrab ();
		public override bool draw (Cairo.Context ctx);
		protected override bool focus_in_event (Gdk.EventFocus focus);
		protected override Gtk.WidgetPath get_path_for_child (Gtk.Widget child);
		protected override bool grab_broken_event (Gdk.EventGrabBroken event);
		protected override void hide ();
		protected override bool map_event (Gdk.EventAny event);
		public override void realize ();
		public override void show ();
		protected bool bottom_tail { protected get; protected set; }
		public Gtk.Widget? relative_to { get; set construct; }
	}
	[CCode (cheader_filename = "BudgieWidgets.h")]
	public class Sidebar : Gtk.Bin {
		public Sidebar ();
		public void set_stack (Gtk.Stack? stack);
	}
	[CCode (cheader_filename = "BudgieWidgets.h")]
	public struct PropChange {
		public string property;
		public GLib.Value old;
		public GLib.Value @new;
	}
	[CCode (cheader_filename = "BudgieWidgets.h")]
	public delegate void AnimCompletionFunc (Budgie.Animation? src);
	[CCode (cheader_filename = "BudgieWidgets.h")]
	public delegate double TweenFunc (double factor);
	[CCode (cheader_filename = "BudgieWidgets.h")]
	public const int64 MSECOND;
	[CCode (cheader_filename = "BudgieWidgets.h")]
	public static double back_ease_in (double p);
	[CCode (cheader_filename = "BudgieWidgets.h")]
	public static double back_ease_out (double p);
	[CCode (cheader_filename = "BudgieWidgets.h")]
	public static double circ_ease_in (double p);
	[CCode (cheader_filename = "BudgieWidgets.h")]
	public static double circ_ease_out (double p);
	[CCode (cheader_filename = "BudgieWidgets.h")]
	public static double elastic_ease_in (double p);
	[CCode (cheader_filename = "BudgieWidgets.h")]
	public static double elastic_ease_out (double p);
	[CCode (cheader_filename = "BudgieWidgets.h")]
	public static double expo_ease_in (double p);
	[CCode (cheader_filename = "BudgieWidgets.h")]
	public static double expo_ease_out (double p);
	[CCode (cheader_filename = "BudgieWidgets.h")]
	public static double quad_ease_in (double p);
	[CCode (cheader_filename = "BudgieWidgets.h")]
	public static double quad_ease_in_out (double p);
	[CCode (cheader_filename = "BudgieWidgets.h")]
	public static double quad_ease_out (double p);
	[CCode (cheader_filename = "BudgieWidgets.h")]
	public static double sine_ease_in (double p);
	[CCode (cheader_filename = "BudgieWidgets.h")]
	public static double sine_ease_in_out (double p);
	[CCode (cheader_filename = "BudgieWidgets.h")]
	public static double sine_ease_out (double p);
}
[CCode (cheader_filename = "BudgieWidgets.h")]
public class InkManager : GLib.Object {
	public InkManager (Gtk.Widget? widget);
	public void add_ripple (double x, double y);
	public void clear_ripples ();
	public void remove_ripple ();
	public void render (Cairo.Context cr, double x, double y, double width, double height);
}
[CCode (cheader_filename = "BudgieWidgets.h")]
public class PaperButton : Gtk.ToggleButton {
	public PaperButton ();
	public override bool button_press_event (Gdk.EventButton btn);
	public override bool button_release_event (Gdk.EventButton btn);
	public override bool draw (Cairo.Context cr);
	public bool anim_above_content { get; set; }
}
