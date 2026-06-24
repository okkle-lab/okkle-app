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

export const numberKeyboardDoneProps: Pick<
  TextInputProps,
  'inputAccessoryViewID' | 'onSubmitEditing' | 'returnKeyType' | 'submitBehavior'
> = {
  inputAccessoryViewID: Platform.OS === 'ios' ? accessoryID : undefined,
  onSubmitEditing: Keyboard.dismiss,
  returnKeyType: 'done',
  submitBehavior: 'blurAndSubmit',
};

export function KeyboardDoneAccessory() {
  if (Platform.OS !== 'ios') return null;

  return (
    <InputAccessoryView nativeID={accessoryID}>
      <View style={s.bar}>
        <Pressable onPress={Keyboard.dismiss} hitSlop={8} style={s.button}>
          <Text style={s.buttonText}>Done</Text>
        </Pressable>
      </View>
    </InputAccessoryView>
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
});
