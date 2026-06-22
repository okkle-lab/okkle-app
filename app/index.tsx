import { Redirect } from 'expo-router';
import { getUser } from '../src/db';

export default function Index() {
  const user = getUser();
  return <Redirect href={user?.onboarded ? '/(tabs)' : '/onboarding'} />;
}
