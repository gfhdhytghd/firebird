import Firebird.Emu 1.0
import Firebird.UIComponents 1.0

import QtQuick 2.0
import QtQuick.Controls 1.2
import QtQuick.Dialogs 1.1
import QtQuick.Layouts 1.0
import QtQuick.Window 2.2

ApplicationWindow {
    id: app
    title: "Firebird Emu"
    visible: true
    color: "black"

    property bool closeAfterSuspend: false
    property bool ignoreSuspendOnClose: false
    property int safeTop: 0
    property int safeLeft: 0
    property int safeRight: 0

    function updateSafeArea() {
        if (!Emu.isMobile())
            return;
        safeTop = Emu.safeAreaTop();
        safeLeft = Emu.safeAreaLeft();
        safeRight = Emu.safeAreaRight();
    }

    visibility: Emu.isMobile() ? Window.FullScreen : Window.Windowed
    onXChanged: if (!Emu.isMobile()) Emu.mobileX = x
    onYChanged: if (!Emu.isMobile()) Emu.mobileY = y
    width: Emu.isMobile() ? Screen.width : (Emu.mobileWidth != -1 ? Emu.mobileWidth : 320)
    onWidthChanged: {
        if (!Emu.isMobile()) Emu.mobileWidth = width;
        updateSafeArea();
    }
    height: Emu.isMobile() ? Screen.height : (Emu.mobileHeight != -1 ? Emu.mobileHeight : 480)
    onHeightChanged: {
        if (!Emu.isMobile()) Emu.mobileHeight = height;
        updateSafeArea();
    }

    minimumWidth: 320
    minimumHeight: 480

    Timer {
        interval: 500
        running: Emu.isMobile()
        repeat: true
        onTriggered: app.updateSafeArea()
    }

    Component.onCompleted: {
        if(Emu.isMobile())
        {
            Emu.useDefaultKit();

            if(Emu.autostart
                && Emu.getFlashPath() !== ""
                && Emu.getBoot1Path() !== "")
            {
                if(Emu.getSnapshotPath() !== "")
                    Emu.resume();
                else
                    Emu.restart();
            }
        }
        else
        {
            if(Emu.mobileX != -1)
                x = Emu.mobileX;

            if(Emu.mobileY != -1)
                y = Emu.mobileY;
        }
    }

    onClosing: {
        if(!Emu.isRunning || !Emu.suspendOnClose || ignoreSuspendOnClose)
            return;

        closeAfterSuspend = true;
        Emu.suspend();
        close.accepted = false;
    }

    MessageDialog {
        id: suspendFailedDialog
        standardButtons: StandardButton.Yes | StandardButton.No
        icon: StandardIcon.Warning
        title: qsTr("Suspend failed")
        text: qsTr("Suspending the emulation failed. Do you still want to quit Firebird?")

        onYes: {
            ignoreSuspendOnClose = true;
            app.close();
        }
    }

    Connections {
        target: Emu
        onEmuSuspended: {
            if(closeAfterSuspend)
            {
                closeAfterSuspend = false;

                if(success)
                {
                    ignoreSuspendOnClose = true;
                    app.close();
                }
                else
                    suspendFailedDialog.visible = true;
            }
        }
        onToastMessage: {
            toast.showMessage(msg);
        }
    }

    Connections {
        target: Qt.application
        onStateChanged: {
            switch (Qt.application.state)
            {
                case Qt.ApplicationSuspended: // Might be reaped on mobile
                    // fallthrough
                case Qt.ApplicationInactive: // Not focused
                    // fallthrough
                case Qt.ApplicationHidden: // Not visible
                    if(Emu.isMobile()) // Keep running on desktop
                        Emu.setPaused(true);
                break;
                case Qt.ApplicationActive: // Visible and in focus
                    if(Emu.isMobile()) // Only unpause if paused
                        Emu.setPaused(false);
                break;
            }
        }
    }

    Toast {
        id: toast
        x: 60
        z: 1

        anchors.bottom: parent.bottom
        anchors.bottomMargin: 61
        anchors.horizontalCenter: parent.horizontalCenter
    }

    ListView {
        id: listView

        focus: true

        anchors {
            fill: parent
            topMargin: app.safeTop
            leftMargin: app.safeLeft
            rightMargin: app.safeRight
        }
        orientation: Qt.Horizontal
        snapMode: ListView.SnapOneItem
        boundsBehavior: ListView.StopAtBounds
        pixelAligned: true

        // Keep the pages alive
        cacheBuffer: width * count

        model: [ "MobileUIConfig.qml", "MobileUIDrawer.qml", "MobileUIFront.qml" ]

        /* The delegates write their X offsets into this array, so that we can use
           them as values for contentX. */
        property var pageX: []

        Component.onCompleted: {
            // Open drawer if emulation does not start automatically
            Emu.useDefaultKit(); // We need this here to get the default values
            if(!Emu.autostart
               || Emu.getBoot1Path() === ""
               || Emu.getFlashPath() === "")
                positionViewAtIndex(1, ListView.SnapPosition);
            else
                positionViewAtIndex(2, ListView.SnapPosition);
        }

        NumberAnimation {
            id: anim
            target: listView
            property: "contentX"
            duration: 200
            easing.type: Easing.InQuad
        }

        function animateToIndex(i) {
            anim.to = pageX[i];
            anim.from = listView.contentX;
            anim.start();
        }

        function closeDrawer() {
            animateToIndex(2);
        }

        function openDrawer() {
            animateToIndex(1);
        }

        function openConfiguration() {
            animateToIndex(0);
        }

        delegate: Item {
            // The pages are expensive, keep them
            ListView.delayRemove: true

            Component.onCompleted: {
                listView.pageX[index] = x;
            }

            onXChanged: {
                listView.pageX[index] = x;
            }

            width: modelData === "MobileUIDrawer.qml" ? loader.item.implicitWidth : listView.width
            height: listView.height

            Rectangle {
                id: overlay
                z: 1
                anchors.fill: parent
                color: "black"
                opacity: {
                    var xOffset = listView.contentX - parent.x;
                    return Math.min(Math.max(0.0, Math.abs(xOffset) / listView.width), 0.6);
                }
                visible: opacity > 0.01

                MouseArea {
                    anchors.fill: parent
                    enabled: parent.visible

                    onReleased: {
                        listView.animateToIndex(index)
                    }
                }
            }

            Loader {
                id: loader
                z: 0
                focus: Math.round(parent.x) == Math.round(listView.contentX);
                anchors.fill: parent
                source: modelData
            }
        }
    }
}
