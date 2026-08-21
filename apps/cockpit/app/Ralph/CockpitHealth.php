<?php

namespace App\Ralph;

use Illuminate\Support\Facades\DB;
use Throwable;

final class CockpitHealth
{
    /**
     * @return list<array{key: string, value: string, ok: bool}>
     */
    public function snapshot(): array
    {
        return [
            $this->reverb(),
            [
                'key' => 'laravel',
                'value' => app()->version(),
                'ok' => true,
            ],
            $this->database(),
            [
                'key' => 'php',
                'value' => PHP_VERSION,
                'ok' => true,
            ],
            $this->ingest(),
            $this->debugCommand(),
        ];
    }

    /**
     * @return array{key: string, value: string, ok: bool}
     */
    private function reverb(): array
    {
        $host = (string) config('broadcasting.connections.reverb.options.host', '');
        if ($host === '' || $host === '0.0.0.0') {
            $host = '127.0.0.1';
        }

        $port = (int) config('broadcasting.connections.reverb.options.port', 8080);
        $serverPort = (int) config('reverb.servers.reverb.port', 8080);
        if ($port <= 0 || $port === 443) {
            $port = $serverPort > 0 ? $serverPort : 8080;
        }

        $errno = 0;
        $errstr = '';
        $socket = @fsockopen($host, $port, $errno, $errstr, 0.25);
        $ok = is_resource($socket);
        if ($ok) {
            fclose($socket);
        }

        return [
            'key' => 'reverb',
            'value' => $ok ? $host.':'.$port : $host.':'.$port.' · off',
            'ok' => $ok,
        ];
    }

    /**
     * @return array{key: string, value: string, ok: bool}
     */
    private function database(): array
    {
        $driver = (string) config('database.default');
        try {
            $version = match ($driver) {
                'sqlite' => (string) (DB::selectOne('select sqlite_version() as v')?->v ?? ''),
                default => $this->serverVersion(),
            };
        } catch (Throwable) {
            return [
                'key' => 'database',
                'value' => $driver.' · offline',
                'ok' => false,
            ];
        }

        return [
            'key' => 'database',
            'value' => $version === '' ? $driver : $driver.' '.$version,
            'ok' => true,
        ];
    }

    private function serverVersion(): string
    {
        $raw = (string) (DB::selectOne('select version() as v')?->v ?? '');
        if (preg_match('/^[^\s]+/', $raw, $match) === 1) {
            return $match[0];
        }

        return $raw;
    }

    /**
     * @return array{key: string, value: string, ok: bool}
     */
    private function ingest(): array
    {
        foreach (glob('/proc/[0-9]*/cmdline') ?: [] as $file) {
            $cmdline = str_replace("\0", ' ', (string) @file_get_contents($file));
            if (str_contains($cmdline, 'ralph:ingest') && str_contains($cmdline, '--follow')) {
                return ['key' => 'ingest', 'value' => 'follow', 'ok' => true];
            }
        }

        return ['key' => 'ingest', 'value' => 'off', 'ok' => false];
    }

    /**
     * @return array{key: string, value: string, ok: bool}
     */
    private function debugCommand(): array
    {
        $ok = app(RalphLauncher::class)->debugCommandLine() !== null;

        return [
            'key' => 'debug',
            'value' => $ok ? 'diagnose' : 'off',
            'ok' => $ok,
        ];
    }
}
