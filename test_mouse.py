# /// script
# dependencies = [
#   "pyside6==6.7.2"
# ]
# ///

import sys

from PySide6.QtWidgets import QApplication, QWidget, QHBoxLayout, QLabel


class Main(QWidget):


    def __init__(self, parent=None):
        super(Main, self).__init__(parent)
        QHBoxLayout(self).addWidget(QLabel("window"))


    def mousePressEvent(self, event):
        print(event.modifiers())


def main():
    app = QApplication(sys.argv)
    (_ := Main()).show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
