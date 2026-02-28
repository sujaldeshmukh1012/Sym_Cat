import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

export const isSupabaseConfigured = Boolean(supabaseUrl && supabaseAnonKey)

function createNoopQueryBuilder(message) {
	const result = { data: [], error: new Error(message), count: 0 }
	const builder = {
		select() { return builder },
		insert() { return builder },
		update() { return builder },
		delete() { return builder },
		order() { return builder },
		limit() { return builder },
		lt() { return builder },
		eq() { return builder },
		then(resolve) { return Promise.resolve(result).then(resolve) },
		catch(reject) { return Promise.resolve(result).catch(reject) },
		finally(onFinally) { return Promise.resolve(result).finally(onFinally) },
	}
	return builder
}

function createNoopSupabaseClient(message) {
	return {
		from() {
			return createNoopQueryBuilder(message)
		},
	}
}

const missingEnvMessage =
	'Supabase is not configured. Add VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY to your .env file.'

if (!isSupabaseConfigured) {
	console.warn(missingEnvMessage)
}

export const supabase = isSupabaseConfigured
	? createClient(supabaseUrl, supabaseAnonKey)
	: createNoopSupabaseClient(missingEnvMessage)
