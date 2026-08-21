<?php

namespace App\Ralph;

use App\Models\WorkflowProjection;

final class CockpitTone
{
    /**
     * @param  array{ready?: bool, running?: bool, reason?: string, cursor_state?: ?string, can_resume?: bool, can_recover?: bool}|null  $launch
     * @return 'ok'|'attention'|'lock'
     */
    public function for(?array $launch, ?WorkflowProjection $workflow): string
    {
        $launch ??= [];
        $health = $workflow?->health;
        $state = is_string($launch['cursor_state'] ?? null) ? $launch['cursor_state'] : null;
        $reason = (string) ($launch['reason'] ?? '');
        $stuck = ($launch['can_resume'] ?? false)
            || ($launch['can_recover'] ?? false)
            || in_array($state, ['recovery_required', 'blocked', 'debugging_required'], true)
            || in_array($reason, ['cockpit.run.recovery_required', 'cockpit.run.debug_required'], true);

        if ($stuck || $health === 'error') {
            return 'lock';
        }

        if ($health === 'warning') {
            return 'attention';
        }

        if ($launch['running'] ?? false) {
            return 'ok';
        }

        if (($launch['ready'] ?? false) === false && ! in_array($reason, [
            '',
            'cockpit.run.ready',
            'cockpit.run.queue_empty',
            'cockpit.run.no_workflow',
        ], true)) {
            return 'attention';
        }

        return 'ok';
    }
}
