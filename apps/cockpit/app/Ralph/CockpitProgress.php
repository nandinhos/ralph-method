<?php

namespace App\Ralph;

use App\Models\WorkflowProjection;
use Illuminate\Support\Collection;

final class CockpitProgress
{
    /**
     * @param  Collection<int, \App\Models\FeatureProjection>  $features
     * @param  Collection<string, Collection<int, \App\Models\GateProjection>>  $gates
     * @return array{
     *     percent: int,
     *     label: string,
     *     detail: string,
     *     feature_slot_percent: int,
     *     active: bool,
     * }
     */
    public function forHud(WorkflowProjection $workflow, Collection $features, Collection $gates): array
    {
        $monitor = is_array($workflow->monitor_payload) ? $workflow->monitor_payload : [];
        $progress = is_array($monitor['progress'] ?? null) ? $monitor['progress'] : [];
        $loop = is_array($monitor['loop_feedback'] ?? null) ? $monitor['loop_feedback'] : [];
        $phase = is_array($loop['phase'] ?? null) ? $loop['phase'] : [];

        $totalFeatures = max(1, (int) ($progress['total_features'] ?? $features->count() ?: 1));
        $completedFeatures = (int) ($progress['completed_features'] ?? $features->whereIn('status', ['released', 'approved'])->count());
        $passedGates = (int) ($progress['passed_gates'] ?? $gates->flatten()->where('status', 'passed')->count());
        $totalGates = max(1, (int) ($progress['total_gates'] ?? 5));
        $position = max(1, min($totalFeatures, (int) ($monitor['position'] ?? $completedFeatures + 1)));

        $state = is_string($monitor['state'] ?? null) ? $monitor['state'] : ($workflow->state ?? '');
        $active = in_array($state, ['running', 'awaiting_gates', 'debugging_running'], true);

        $phaseNum = is_numeric($phase['number'] ?? null) ? (int) $phase['number'] : null;
        $phaseTotal = is_numeric($phase['total'] ?? null) ? max(1, (int) $phase['total']) : null;
        $phaseTitle = is_string($phase['title'] ?? null) ? trim($phase['title']) : '';

        $inFeature = 0.0;
        if ($completedFeatures < $totalFeatures) {
            if ($active) {
                $inFeature = 0.12;
            }
            if ($phaseNum !== null && $phaseTotal !== null) {
                $phaseDone = max(0, min($phaseTotal, $phaseNum - (($loop['event'] ?? '') === 'phase_start' ? 1 : 0)));
                $inFeature = max($inFeature, $phaseDone / $phaseTotal * 0.55);
            }
            $inFeature += ($passedGates / $totalGates) * 0.33;
            $inFeature = min(0.99, $inFeature);
        }

        $stored = (int) ($workflow->progress_percent ?? 0);
        $estimated = is_numeric($progress['estimated_percent'] ?? null)
            ? (int) round((float) $progress['estimated_percent'])
            : $stored;
        $computed = (int) round((($completedFeatures + $inFeature) / $totalFeatures) * 100);
        $percent = max($stored, $estimated, $computed);

        $featureSlotPercent = (int) round(min(100, $inFeature * 100));

        $phaseLabel = ($phaseNum !== null && $phaseTotal !== null) ? "{$phaseNum}/{$phaseTotal}" : '—';
        $detail = __('cockpit.progress.detail', [
            'feature' => $position,
            'features' => $totalFeatures,
            'gates' => $passedGates,
            'gate_total' => $totalGates,
            'phase' => $phaseLabel,
        ]);

        if ($phaseTitle !== '') {
            $detail .= ' · '.$phaseTitle;
        }

        $label = $percent > 0 || ! $active ? 'workflow' : 'ativo';

        return [
            'percent' => min(100, max(0, $percent)),
            'label' => $label,
            'detail' => $detail,
            'feature_slot_percent' => $featureSlotPercent,
            'active' => $active,
        ];
    }
}
