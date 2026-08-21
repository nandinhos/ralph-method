<?php

use App\Livewire\Cockpit\TraceCockpit;
use App\Models\FeatureProjection;
use App\Models\WorkflowProjection;
use Livewire\Livewire;

it('renderiza o cockpit vazio sem projeção', function () {
    $this->get('/')
        ->assertOk()
        ->assertSee('Nenhum workflow ingerido', false)
        ->assertSee('window.RalphCockpit', false);
});

it('mostra a feature projetada', function () {
    WorkflowProjection::factory()->create([
        'workflow_id' => 'wf_cockpit_demo',
        'engine' => 'cursor',
        'cursor_feature_key' => 'FEATURE-092',
        'progress_percent' => 68,
        'health' => 'ok',
    ]);
    FeatureProjection::factory()->create([
        'workflow_id' => 'wf_cockpit_demo',
        'feature_key' => 'FEATURE-092',
        'title' => 'Evoluir e restaurar',
        'status' => 'running',
        'engine' => 'cursor',
    ]);

    Livewire::test(TraceCockpit::class)
        ->assertSee('FEATURE-092')
        ->assertSee('Evoluir e restaurar')
        ->assertSee('cursor')
        ->assertSee('Rodar Ralph')
        ->assertSee('Laravel')
        ->assertDontSee('Uma visão premium')
        ->assertDontSee('approve');
});
