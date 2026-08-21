<?php

use App\Models\FeatureProjection;
use App\Models\WorkflowProjection;
use App\Ralph\CockpitProgress;

it('projeta progresso parcial quando a feature está rodando sem gates', function () {
    $workflow = WorkflowProjection::query()->create([
        'workflow_id' => 'wf_progress_demo',
        'state' => 'running',
        'progress_percent' => 0,
        'monitor_payload' => [
            'state' => 'running',
            'position' => 1,
            'loop_feedback' => [
                'event' => 'phase_start',
                'phase' => [
                    'number' => 1,
                    'total' => 1,
                    'title' => 'Campo opt-in Cursor',
                ],
                'progress' => ['percent' => 0],
            ],
            'progress' => [
                'total_features' => 4,
                'completed_features' => 0,
                'passed_gates' => 0,
                'total_gates' => 5,
                'estimated_percent' => 0,
            ],
        ],
    ]);

    FeatureProjection::query()->create([
        'workflow_id' => 'wf_progress_demo',
        'feature_key' => 'FEATURE-100A',
        'title' => 'Campo opt-in',
        'position' => 1,
        'status' => 'running',
        'engine' => 'cursor',
    ]);

    $hud = app(CockpitProgress::class)->forHud(
        $workflow,
        FeatureProjection::query()->where('workflow_id', 'wf_progress_demo')->get(),
        collect(),
    );

    expect($hud['percent'])->toBeGreaterThan(0)
        ->and($hud['active'])->toBeTrue()
        ->and($hud['feature_slot_percent'])->toBeGreaterThan(0)
        ->and($hud['detail'])->toContain('feature 1/4');
});

it('prioriza progresso estimado do monitor quando disponível', function () {
    $workflow = WorkflowProjection::query()->create([
        'workflow_id' => 'wf_progress_monitor',
        'progress_percent' => 18,
        'monitor_payload' => [
            'state' => 'running',
            'position' => 2,
            'progress' => [
                'total_features' => 4,
                'completed_features' => 1,
                'passed_gates' => 2,
                'total_gates' => 5,
                'estimated_percent' => 18,
            ],
        ],
    ]);

    $hud = app(CockpitProgress::class)->forHud(
        $workflow,
        collect(),
        collect(),
    );

    expect($hud['percent'])->toBeGreaterThanOrEqual(18);
});
