import React from 'react';
import {
  InputAccessoryView,
  Keyboard,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import type { TextInputProps } from 'react-native';
import { colors, font, spacing } from '../theme';

const accessoryID = 'okkle-number-keyboard-done';
const listeners = new Set<(focused: boolean) => void>();
let numberKeyboardFocused = false;

function setNumberKeyboardFocused(focused: boolean) {
  numberKeyboardFocused = focused;
  listeners.forEach(listener => listener(focused));
}

function dismissKeyboard() {
  setNumberKeyboardFocused(false);
  Keyboard.dismiss();
}

export const numberKeyboardDoneProps: Pick<
  TextInputProps,
  | 'blurOnSubmit'
  | 'inputAccessoryViewID'
  | 'onBlur'
  | 'onFocus'
  | 'onSubmitEditing'
  | 'returnKeyType'
  | 'submitBehavior'
> = {
  blurOnSubmit: true,
  inputAccessoryViewID: Platform.OS === 'ios' ? accessoryID : undefined,
  onBlur: () => setNumberKeyboardFocused(false),
  onFocus: () => setNumberKeyboardFocused(true),
  onSubmitEditing: dismissKeyboard,
  returnKeyType: 'done',
  submitBehavior: 'blurAndSubmit',
};

export function KeyboardDoneAccessory() {
  const [focused, setFocused] = React.useState(numberKeyboardFocused);
  const [keyboardVisible, setKeyboardVisible] = React.useState(false);

  React.useEffect(() => {
    const listener = (nextFocused: boolean) => setFocused(nextFocused);
    listeners.add(listener);

    const shown = Keyboard.addListener('keyboardDidShow', () => setKeyboardVisible(true));
    const hidden = Keyboard.addListener('keyboardDidHide', () => {
      setKeyboardVisible(false);
      setNumberKeyboardFocused(false);
    });

    return () => {
      listeners.delete(listener);
      shown.remove();
      hidden.remove();
    };
  }, []);

  const button = (
    <Pressable onPress={dismissKeyboard} hitSlop={8} style={s.button}>
      <Text style={s.buttonText}>Done</Text>
    </Pressable>
  );

  if (Platform.OS === 'ios') {
    return (
      <InputAccessoryView nativeID={accessoryID}>
        <View style={s.bar}>
          {button}
        </View>
      </InputAccessoryView>
    );
  }

  if (!focused || !keyboardVisible) return null;

  return (
    <View pointerEvents="box-none" style={s.androidOverlay}>
      <View style={s.androidPill}>
        {button}
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  bar: {
    alignItems: 'flex-end',
    backgroundColor: colors.bgCard,
    borderTopColor: colors.border,
    borderTopWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: spacing.lg,
    paddingVertical: 8,
  },
  button: {
    paddingHorizontal: spacing.sm,
    paddingVertical: 6,
  },
  buttonText: {
    color: colors.brandDeep,
    fontSize: 16,
    fontWeight: font.semibold,
  },
  androidOverlay: {
    position: 'absolute',
    right: spacing.xl,
    bottom: spacing.md,
    zIndex: 50,
  },
  androidPill: {
    backgroundColor: colors.bgCard,
    borderColor: colors.border,
    borderRadius: 18,
    borderWidth: StyleSheet.hairlineWidth,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.14,
    shadowRadius: 12,
    elevation: 8,
  },
});
