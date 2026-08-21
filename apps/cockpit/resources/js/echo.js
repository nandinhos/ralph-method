import Echo from 'laravel-echo';

import Pusher from 'pusher-js';
window.Pusher = Pusher;

const runtime = window.RalphCockpit?.reverb ?? {};
const scheme = runtime.scheme ?? import.meta.env.VITE_REVERB_SCHEME ?? 'http';
const port = Number(runtime.port ?? import.meta.env.VITE_REVERB_PORT ?? 8080);

window.Echo = new Echo({
    broadcaster: 'reverb',
    key: runtime.key ?? import.meta.env.VITE_REVERB_APP_KEY,
    wsHost: runtime.host ?? import.meta.env.VITE_REVERB_HOST ?? '127.0.0.1',
    wsPort: port,
    wssPort: port,
    forceTLS: scheme === 'https',
    enabledTransports: ['ws', 'wss'],
});
