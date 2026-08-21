<!DOCTYPE html>
<html lang="{{ str_replace('_', '-', app()->getLocale()) }}">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{ __('cockpit.title') }}</title>
    <script>
        window.RalphCockpit = {
            reverb: {
                key: @json((string) config('broadcasting.connections.reverb.key')),
                host: @json((string) (config('broadcasting.connections.reverb.options.host') ?: '127.0.0.1')),
                port: {{ (int) (config('broadcasting.connections.reverb.options.port') ?: 8080) }},
                scheme: @json((string) (config('broadcasting.connections.reverb.options.scheme') ?: 'http')),
            },
        };
    </script>
    @vite(['resources/css/app.css', 'resources/js/app.js'])
    @livewireStyles
</head>
<body class="min-h-screen bg-rt-bg text-rt-text font-sans antialiased">
    {{ $slot }}
    @livewireScripts
</body>
</html>
