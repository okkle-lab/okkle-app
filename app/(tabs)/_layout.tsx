import { Feather } from '@expo/vector-icons';
import { DynamicColorIOS, Platform } from 'react-native';
import { NativeTabs } from 'expo-router/unstable-native-tabs';
import type { ComponentProps } from 'react';
import type { SFSymbol } from 'sf-symbols-typescript';
import { colors, font } from '../../src/theme';

type FeatherName = ComponentProps<typeof Feather>['name'];

type TabItem = {
  name: string;
  label: string;
  feather: FeatherName;
  sf: {
    default: SFSymbol;
    selected: SFSymbol;
  };
};

const tabTint = Platform.OS === 'ios'
  ? DynamicColorIOS({ light: '#0E8E78', dark: '#7FD6C5' })
  : colors.brandDeep;

const tabLabel = Platform.OS === 'ios'
  ? DynamicColorIOS({ light: '#22302C', dark: '#EEF5F1' })
  : colors.textSecondary;

const tabs: TabItem[] = [
  { name: 'index', label: 'Home', feather: 'user', sf: { default: 'person.crop.circle', selected: 'person.crop.circle.fill' } },
  { name: 'insights', label: 'Insights', feather: 'zap', sf: { default: 'sparkles', selected: 'sparkles' } },
  { name: 'trip', label: 'Trip', feather: 'navigation', sf: { default: 'location.north', selected: 'location.north.fill' } },
  { name: 'log', label: 'Log', feather: 'edit-3', sf: { default: 'square.and.pencil', selected: 'square.and.pencil' } },
  { name: 'records', label: 'Records', feather: 'archive', sf: { default: 'archivebox', selected: 'archivebox.fill' } },
];

export default function TabLayout() {
  return (
    <NativeTabs
      backgroundColor="transparent"
      blurEffect="systemChromeMaterial"
      iconColor={{ default: tabLabel, selected: tabTint }}
      labelStyle={{ color: tabLabel, fontSize: 11, fontWeight: font.semibold }}
      minimizeBehavior="onScrollDown"
      shadowColor="transparent"
      tintColor={tabTint}
    >
      {tabs.map(tab => (
        <NativeTabs.Trigger key={tab.name} name={tab.name}>
          <NativeTabs.Trigger.Icon
            sf={tab.sf}
            src={<NativeTabs.Trigger.VectorIcon family={Feather} name={tab.feather} />}
          />
          <NativeTabs.Trigger.Label>{tab.label}</NativeTabs.Trigger.Label>
        </NativeTabs.Trigger>
      ))}
    </NativeTabs>
  );
}
