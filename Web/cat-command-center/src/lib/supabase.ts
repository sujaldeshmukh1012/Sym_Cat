import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;

export const isSupabaseConfigured = Boolean(supabaseUrl && supabaseAnonKey);

/* eslint-disable @typescript-eslint/no-explicit-any */
function createNoopQueryBuilder(message: string): any {
  const result = { data: [], error: new Error(message), count: 0 };
  const builder: any = {
    select() { return builder; },
    insert() { return builder; },
    update() { return builder; },
    delete() { return builder; },
    order() { return builder; },
    limit() { return builder; },
    lt() { return builder; },
    eq() { return builder; },
    then(resolve: any) { return Promise.resolve(result).then(resolve); },
    catch(reject: any) { return Promise.resolve(result).catch(reject); },
    finally(onFinally: any) { return Promise.resolve(result).finally(onFinally); },
  };
  return builder;
}

function createNoopSupabaseClient(message: string) {
  return {
    from() {
      return createNoopQueryBuilder(message);
    },
  };
}
/* eslint-enable @typescript-eslint/no-explicit-any */

const missingEnvMessage =
  'Supabase is not configured. Add VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY to your .env file.';

if (!isSupabaseConfigured) {
  console.warn(missingEnvMessage);
}

export const supabase: any = isSupabaseConfigured
  ? createClient(supabaseUrl!, supabaseAnonKey!)
  : createNoopSupabaseClient(missingEnvMessage);
