// The clock in the right corner, as on macOS and Windows. GNOME has no
// setting for it, and the panel puts all items back in place on a session
// mode change, e.g. unlock, so the clock is moved again after that.

import Clutter from 'gi://Clutter';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

export default class ClockRightExtension extends Extension {
  enable() {
    this._moveTo(Main.panel._rightBox, -1, Clutter.ActorAlign.END);
    Main.sessionMode.connectObject('updated', () => {
      this._moveTo(Main.panel._rightBox, -1, Clutter.ActorAlign.END);
    }, this);
  }

  disable() {
    Main.sessionMode.disconnectObject(this);
    this._moveTo(Main.panel._centerBox, 0, Clutter.ActorAlign.CENTER);
  }

  // Notifications drop down under the clock, as the panel does when a
  // session mode puts it on a side
  _moveTo(box, index, bannerAlignment) {
    const container = Main.panel.statusArea.dateMenu?.container;
    if (!container) {
      return;
    }
    container.get_parent()?.remove_child(container);
    box.insert_child_at_index(container, index);
    Main.messageTray.bannerAlignment = bannerAlignment;
  }
}
