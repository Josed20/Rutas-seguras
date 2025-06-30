import 'package:flutter/material.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';

class KeyboardDismissDemo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return KeyboardDismissOnTap(
      child: Scaffold(
        appBar: AppBar(
          title: Text('Keyboard Dismiss Demo'),
        ),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                TextField(
                  decoration: InputDecoration(
                    labelText: 'Tap outside to dismiss keyboard',
                  ),
                ),
                SizedBox(height: 20),
                Text('Tap anywhere on the screen to dismiss the keyboard'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
