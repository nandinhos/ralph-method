<?php

use App\Models\WorkflowProjection;
use App\Ralph\CockpitTone;

it('marca trava quando a feature está em recovery', function () {
    $workflow = WorkflowProjection::factory()->make(['health' => 'ok']);

    expect(app(CockpitTone::class)->for([
        'ready' => false,
        'running' => false,
        'reason' => 'cockpit.run.recovery_required',
        'cursor_state' => 'recovery_required',
        'can_resume' => true,
        'can_recover' => true,
    ], $workflow))->toBe('lock');
});

it('marca atenção quando o plano declarado está ausente', function () {
    $workflow = WorkflowProjection::factory()->make(['health' => 'ok']);

    expect(app(CockpitTone::class)->for([
        'ready' => false,
        'running' => false,
        'reason' => 'cockpit.run.plan_missing',
        'cursor_state' => 'pending',
        'can_resume' => false,
        'can_recover' => false,
    ], $workflow))->toBe('attention');
});

it('marca atenção quando o preflight falha sem trava da fila', function () {
    $workflow = WorkflowProjection::factory()->make(['health' => 'ok']);

    expect(app(CockpitTone::class)->for([
        'ready' => false,
        'running' => false,
        'reason' => 'cockpit.run.dirty_tree',
        'cursor_state' => 'pending',
        'can_resume' => false,
        'can_recover' => false,
    ], $workflow))->toBe('attention');
});

it('marca ok quando o monitor está saudável e o supervise corre', function () {
    $workflow = WorkflowProjection::factory()->make(['health' => 'ok']);

    expect(app(CockpitTone::class)->for([
        'ready' => false,
        'running' => true,
        'reason' => 'cockpit.run.already_running',
        'cursor_state' => 'running',
        'can_resume' => false,
        'can_recover' => false,
    ], $workflow))->toBe('ok');
});

it('marca trava quando a saúde do monitor é erro', function () {
    $workflow = WorkflowProjection::factory()->make(['health' => 'error']);

    expect(app(CockpitTone::class)->for([
        'ready' => true,
        'running' => false,
        'reason' => 'cockpit.run.ready',
        'cursor_state' => 'pending',
        'can_resume' => false,
        'can_recover' => false,
    ], $workflow))->toBe('lock');
});
