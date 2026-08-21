<?php

return [
    'project_root' => env('RALPH_PROJECT_ROOT', dirname(__DIR__, 3)),
    'monitor_bin' => env('RALPH_MONITOR_BIN'),
    'control_bin' => env('RALPH_CONTROL_BIN'),
    'follow_sleep_seconds' => (int) env('RALPH_INGEST_SLEEP', 1),
    'debug_command' => env('RALPH_DEBUG_COMMAND'),
];
