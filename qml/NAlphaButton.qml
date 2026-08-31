import QtQuick 2.0

NButton {
    width: 18
    height: 18

    // Alphabet rows have a 10px horizontal gutter, but only a narrow vertical
    // gutter.  Split each gutter between its two neighbours.
    hitMarginLeft: 5
    hitMarginRight: 5
    hitMarginTop: 1
    hitMarginBottom: 1
}
