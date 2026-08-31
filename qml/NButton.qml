import QtQuick 2.0
import Firebird.Emu 1.0

Rectangle {
    property string active_color: "#555"
    property string back_color: "#223"
    property string font_color: "#fff"
    property alias text: label.text
    property bool active: pressed || mouseArea.containsMouse
    property bool pressed: false
    // Pressing the right mouse button "locks" the button in enabled state
    property bool fixed: false
    property int keymap_id: 1

    // Keep the key face at its original size, but let the input target use the
    // otherwise empty spacing around it.  Callers can trim individual edges
    // where two key faces touch (NDualButton does this for its centre seam).
    property real hitMarginLeft: 5
    property real hitMarginRight: 5
    property real hitMarginTop: 5
    property real hitMarginBottom: 5
    // Once a touch owns this key, tolerate a small amount of finger drift.
    // The touch remains grabbed by this area, so moving across the keypad does
    // not press a neighbouring key.
    property real releaseSlop: 3

    signal clicked()

    border.width: active ? 2 : 1
    border.color: "#888"
    radius: 4
    color: active ? active_color : back_color

    onPressedChanged: {
        if(pressed)
            clicked();

        if(!pressed)
            fixed = false;

        Emu.setButtonState(keymap_id, pressed);
    }

    Connections {
        target: Emu
        function onButtonStateChanged(id, state) {
            if(id === keymap_id)
                pressed = state;
        }
    }

    Text {
        id: label
        text: "Foo"
        anchors.fill: parent
        anchors.centerIn: parent
        font.pixelSize: height*0.55
        color: font_color
        font.bold: true
        // Workaround: Text.AutoText doesn't seem to work for properties (?)
        textFormat: text.indexOf(">") == -1 ? Text.PlainText : Text.RichText
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
    }

    // This is needed to support pressing multiple buttons at once on multitouch
    MultiPointTouchArea {
        id: multiMouseArea

        mouseEnabled: Qt.platform.os === "android" || Qt.platform.os === "ios"
        maximumTouchPoints: 1
        minimumTouchPoints: 1

        x: -parent.hitMarginLeft
        y: -parent.hitMarginTop
        width: parent.width + parent.hitMarginLeft + parent.hitMarginRight
        height: parent.height + parent.hitMarginTop + parent.hitMarginBottom

        function updatePressedState() {
            var newState = false;
            for(var i in touchPoints)
            {
                var tp = touchPoints[i];
                if(tp.pressed
                   && tp.x >= -parent.releaseSlop
                   && tp.x < width + parent.releaseSlop
                   && tp.y >= -parent.releaseSlop
                   && tp.y < height + parent.releaseSlop)
                {
                    newState = true;
                    break;
                }
            }

            parent.pressed = newState;
        }

        onPressed: updatePressedState()
        onTouchUpdated: updatePressedState()
        onReleased: parent.pressed = false
        onCanceled: parent.pressed = false
    }

    MouseArea {
        id: mouseArea

        enabled: !multiMouseArea.mouseEnabled

        preventStealing: true

        x: -parent.hitMarginLeft
        y: -parent.hitMarginTop
        width: parent.width + parent.hitMarginLeft + parent.hitMarginRight
        height: parent.height + parent.hitMarginTop + parent.hitMarginBottom
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        hoverEnabled: !Emu.isMobile()

        onPressed: {
            mouse.accepted = true;

            if(mouse.button == Qt.LeftButton)
            {
                if(!fixed)
                    parent.pressed = true;
            }
            else if(fixed === parent.pressed) // Right button
            {
                fixed = !fixed;
                parent.pressed = !parent.pressed;
            }
        }

        onReleased: {
            mouse.accepted = true;

            if(mouse.button == Qt.LeftButton
                    && !fixed)
                parent.pressed = false;
        }

        onCanceled: {
            if(!fixed)
                parent.pressed = false;
        }
    }
}
