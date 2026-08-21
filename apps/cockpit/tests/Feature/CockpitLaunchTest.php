<?php

use App\Livewire\Cockpit\TraceCockpit;
use App\Models\FeatureProjection;
use App\Models\WorkflowProjection;
use App\Ralph\RalphLauncher;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Process;
use Livewire\Livewire;

const COCKPIT_FIELD_SPEC = '099-cockpit-field';
const COCKPIT_FIELD_FEATURE_A = 'FEATURE-099A-COCKPIT-MANIFEST';
const COCKPIT_FIELD_FEATURE_B = 'FEATURE-099B-COCKPIT-INGEST';
const COCKPIT_FIELD_FEATURE_C = 'FEATURE-099C-COCKPIT-SUPERVISE';

function cockpitFieldSpecDir(): string
{
    return dirname(base_path(), 2).'/.spec/features/'.COCKPIT_FIELD_SPEC;
}

function cockpitLaunchRoot(string $workflowId = 'wf_cockpit_field'): string
{
    $root = storage_path('framework/testing/ralph-launch-'.$workflowId);
    File::deleteDirectory($root);
    $spec = cockpitFieldSpecDir();
    $dest = $root.'/.spec/features/'.COCKPIT_FIELD_SPEC;
    File::ensureDirectoryExists($dest);
    File::copy($spec.'/plan.md', $dest.'/plan.md');
    File::copy($spec.'/PHASES.md', $dest.'/PHASES.md');
    File::copy($spec.'/workflow.json', $dest.'/workflow.json');
    File::ensureDirectoryExists($root.'/.git/ralph-control');
    File::copy($dest.'/workflow.json', $root.'/.git/ralph-control/workflow.json');
    File::ensureDirectoryExists($root.'/bin');
    File::put($root.'/bin/ralph-control', "#!/usr/bin/env php\n<?php\n");
    chmod($root.'/bin/ralph-control', 0755);

    config([
        'ralph.project_root' => $root,
        'ralph.control_bin' => $root.'/bin/ralph-control',
    ]);

    $pidFile = storage_path('app/ralph-supervise.pid');
    if (is_file($pidFile)) {
        unlink($pidFile);
    }

    return $root;
}

function fakeCleanGit(): void
{
    Process::fake(function ($process) {
        $command = is_array($process->command) ? implode(' ', $process->command) : (string) $process->command;
        if (str_contains($command, 'git rev-parse')) {
            return Process::result("true\n");
        }
        if (str_contains($command, 'git status')) {
            return Process::result('');
        }

        return Process::result("4242\n");
    });
}

it('recusa o disparo quando não há feature pendente', function () {
    $root = cockpitLaunchRoot();
    fakeCleanGit();

    WorkflowProjection::factory()->create(['workflow_id' => 'wf_cockpit_field']);
    foreach ([COCKPIT_FIELD_FEATURE_A, COCKPIT_FIELD_FEATURE_B, COCKPIT_FIELD_FEATURE_C] as $index => $key) {
        FeatureProjection::factory()->create([
            'workflow_id' => 'wf_cockpit_field',
            'feature_key' => $key,
            'status' => 'released',
            'position' => $index + 1,
        ]);
    }

    $decision = app(RalphLauncher::class)->decision('wf_cockpit_field');

    expect($decision['ready'])->toBeFalse()
        ->and($decision['reason'])->toBe('cockpit.run.queue_empty')
        ->and(is_dir($root))->toBeTrue();
});

it('libera o preflight quando a fila tem feature e o checkout está limpo', function () {
    cockpitLaunchRoot();
    fakeCleanGit();

    WorkflowProjection::factory()->create(['workflow_id' => 'wf_cockpit_field']);
    FeatureProjection::factory()->create([
        'workflow_id' => 'wf_cockpit_field',
        'feature_key' => 'FEATURE-099A-COCKPIT-MANIFEST',
        'title' => 'Manifesto e preflight do checkout de campo',
        'status' => 'pending',
        'position' => 1,
    ]);

    $decision = app(RalphLauncher::class)->decision('wf_cockpit_field');

    expect($decision['ready'])->toBeTrue()
        ->and($decision['next_feature'])->toBe('FEATURE-099A-COCKPIT-MANIFEST')
        ->and($decision['reason'])->toBe('cockpit.run.ready');
});

it('recusa o disparo quando a feature está em recovery', function () {
    cockpitLaunchRoot();
    fakeCleanGit();

    WorkflowProjection::factory()->create(['workflow_id' => 'wf_cockpit_field']);
    FeatureProjection::factory()->create([
        'workflow_id' => 'wf_cockpit_field',
        'feature_key' => 'FEATURE-099A-COCKPIT-MANIFEST',
        'title' => 'Manifesto e preflight do checkout de campo',
        'status' => 'blocked',
        'position' => 1,
    ]);

    $decision = app(RalphLauncher::class)->decision('wf_cockpit_field');

    expect($decision['ready'])->toBeFalse()
        ->and($decision['reason'])->toBe('cockpit.run.recovery_required')
        ->and($decision['can_resume'])->toBeTrue()
        ->and($decision['can_debug'])->toBeTrue()
        ->and($decision['can_recover'])->toBeTrue();
});

it('recusa recover quando a feature não está travada', function () {
    cockpitLaunchRoot();
    fakeCleanGit();

    WorkflowProjection::factory()->create(['workflow_id' => 'wf_cockpit_field']);
    FeatureProjection::factory()->create([
        'workflow_id' => 'wf_cockpit_field',
        'feature_key' => 'FEATURE-099A-COCKPIT-MANIFEST',
        'status' => 'pending',
        'position' => 1,
    ]);

    $result = app(RalphLauncher::class)->recover('wf_cockpit_field');

    expect($result['recovered'])->toBeFalse()
        ->and($result['reason'])->toBe('cockpit.run.recover_unavailable');
});

it('recusa debug quando o comando do cockpit não existe', function () {
    cockpitLaunchRoot();
    config(['ralph.debug_command' => storage_path('framework/testing/missing-ralph-diagnose.php')]);

    WorkflowProjection::factory()->create(['workflow_id' => 'wf_cockpit_field']);
    FeatureProjection::factory()->create([
        'workflow_id' => 'wf_cockpit_field',
        'feature_key' => 'FEATURE-099A-COCKPIT-MANIFEST',
        'status' => 'blocked',
        'position' => 1,
    ]);

    $result = app(RalphLauncher::class)->debug('wf_cockpit_field');

    expect($result['debugged'])->toBeFalse()
        ->and($result['reason'])->toBe('cockpit.run.debug_missing')
        ->and($result['report']['symptom'])->toBe('');
});

it('o diagnostico read-only emite JSON 1.2.0', function () {
    $root = cockpitLaunchRoot();
    $command = 'cd '.escapeshellarg($root)
        .' && RALPH_DEBUG_WORKFLOW_ID=wf_cockpit_field'
        .' RALPH_DEBUG_FEATURE_KEY=FEATURE-099A-COCKPIT-MANIFEST'
        .' RALPH_DEBUG_ATTEMPT=1 '
        .escapeshellarg(PHP_BINARY).' '.escapeshellarg(base_path('bin/ralph-diagnose.php'));
    exec($command, $lines, $code);
    $payload = json_decode(implode("\n", $lines), true);

    expect($code)->toBe(0)
        ->and($payload['schema_version'])->toBe('1.2.0')
        ->and($payload['status'])->toBe('verified')
        ->and($payload['cause_kind'])->toBeIn(['harness_defect', 'feature_bug', 'capacity', 'unknown'])
        ->and($payload['symptom'])->not->toBe('');
});

it('confirma input ausente a partir do stderr do supervisor', function () {
    $root = cockpitLaunchRoot();
    $input = $root.'/.spec/features/'.COCKPIT_FIELD_SPEC.'/PHASES.md';
    File::delete($input);
    File::ensureDirectoryExists($root.'/.git/ralph-control/artifacts');
    File::put(
        $root.'/.git/ralph-control/artifacts/supervisor-'.COCKPIT_FIELD_FEATURE_A.'-retry-0.stderr.log',
        'erro: input da feature não encontrado: '.$input."\n",
    );
    File::put($root.'/.git/ralph-control/events.jsonl', json_encode([
        'feature_key' => 'FEATURE-099A-COCKPIT-MANIFEST',
        'type' => 'recovery.required',
        'facts' => ['reason' => 'processo terminou sem evento terminal'],
    ], JSON_THROW_ON_ERROR)."\n");

    $command = 'cd '.escapeshellarg($root)
        .' && RALPH_DEBUG_WORKFLOW_ID=wf_cockpit_field'
        .' RALPH_DEBUG_FEATURE_KEY=FEATURE-099A-COCKPIT-MANIFEST'
        .' RALPH_DEBUG_ATTEMPT=1 '
        .escapeshellarg(PHP_BINARY).' '.escapeshellarg(base_path('bin/ralph-diagnose.php'));
    exec($command, $lines, $code);
    $payload = json_decode(implode("\n", $lines), true);
    $statuses = array_column($payload['hypotheses'] ?? [], 'status', 'id');

    expect($code)->toBe(0)
        ->and($payload['cause_kind'])->toBe('harness_defect')
        ->and($payload['symptom'])->toContain('PHASES.md')
        ->and($payload['root_cause'])->toContain('PHASES.md')
        ->and($payload['correction_plan'])->toContain('PHASES.md')
        ->and($payload['correction_plan'])->not->toContain('Retomar so sustenta')
        ->and($statuses['H1'] ?? null)->toBe('confirmed')
        ->and($statuses['H2'] ?? null)->toBe('rejected')
        ->and($statuses['H3'] ?? null)->toBe('rejected');
});

it('recusa o disparo quando o input declarado no manifesto está ausente', function () {
    $root = cockpitLaunchRoot();
    $input = $root.'/.spec/features/'.COCKPIT_FIELD_SPEC.'/PHASES.md';
    File::delete($input);
    fakeCleanGit();

    WorkflowProjection::factory()->create(['workflow_id' => 'wf_cockpit_field']);
    FeatureProjection::factory()->create([
        'workflow_id' => 'wf_cockpit_field',
        'feature_key' => COCKPIT_FIELD_FEATURE_A,
        'title' => 'Manifesto e preflight do checkout de campo',
        'status' => 'pending',
        'position' => 1,
    ]);

    $decision = app(RalphLauncher::class)->decision('wf_cockpit_field');
    $started = app(RalphLauncher::class)->start('wf_cockpit_field');

    expect($decision['ready'])->toBeFalse()
        ->and($decision['reason'])->toBe('cockpit.run.plan_missing')
        ->and($decision['can_resume'])->toBeFalse()
        ->and($started['started'])->toBeFalse()
        ->and($started['reason'])->toBe('cockpit.run.plan_missing')
        ->and(is_file($input))->toBeFalse();

    Process::assertDidntRun(function ($process) {
        $command = is_array($process->command) ? implode(' ', $process->command) : (string) $process->command;

        return str_contains($command, 'supervise');
    });
});

it('mostra o diagnóstico gravado no checkout', function () {
    $root = cockpitLaunchRoot();
    fakeCleanGit();
    File::ensureDirectoryExists($root.'/.git/ralph-control/reports');
    File::put($root.'/.git/ralph-control/reports/DBG-2026-0001.json', json_encode([
        'workflow_id' => 'wf_cockpit_field',
        'incident_id' => 'INC-COCKPIT-ORCH-001',
        'symptom' => 'O bloco encerrou sem evento terminal.',
        'root_cause' => 'O runner do checkout nao conclui a feature apos o claim.',
        'correction_plan' => 'Diagnosticar no painel e so retomar com runner capaz de escrever o bloco.',
    ], JSON_THROW_ON_ERROR));

    WorkflowProjection::factory()->create(['workflow_id' => 'wf_cockpit_field']);
    FeatureProjection::factory()->create([
        'workflow_id' => 'wf_cockpit_field',
        'feature_key' => 'FEATURE-099A-COCKPIT-MANIFEST',
        'title' => 'Manifesto e preflight do checkout de campo',
        'status' => 'blocked',
        'position' => 1,
    ]);

    Livewire::test(TraceCockpit::class)
        ->assertSee('Diagnóstico')
        ->assertSee('O bloco encerrou sem evento terminal.')
        ->assertSee('O runner do checkout nao conclui a feature apos o claim.');
});

it('retoma o orquestrador com recover e supervise quando a feature está travada', function () {
    cockpitLaunchRoot();
    $pidFile = storage_path('app/ralph-supervise.pid');
    if (is_file($pidFile)) {
        unlink($pidFile);
    }

    $cursorState = 'recovery_required';
    Process::fake(function ($process) use (&$cursorState) {
        $command = is_array($process->command) ? implode(' ', $process->command) : (string) $process->command;
        if (str_contains($command, 'git rev-parse')) {
            return Process::result("true\n");
        }
        if (str_contains($command, 'git status')) {
            return Process::result('');
        }
        if (str_contains($command, ' recover ')) {
            $cursorState = 'pending';

            return Process::result('{"status":"pending"}'."\n");
        }
        if (str_contains($command, ' status ')) {
            return Process::result(json_encode([
                'projection' => [
                    'cursor' => 'FEATURE-099A-COCKPIT-MANIFEST',
                    'features' => [[
                        'feature_key' => 'FEATURE-099A-COCKPIT-MANIFEST',
                        'state' => $cursorState,
                    ]],
                ],
            ], JSON_THROW_ON_ERROR)."\n");
        }

        return Process::result("4242\n");
    });

    WorkflowProjection::factory()->create(['workflow_id' => 'wf_cockpit_field']);
    FeatureProjection::factory()->create([
        'workflow_id' => 'wf_cockpit_field',
        'feature_key' => 'FEATURE-099A-COCKPIT-MANIFEST',
        'title' => 'Manifesto e preflight do checkout de campo',
        'status' => 'blocked',
        'position' => 1,
    ]);

    $result = app(RalphLauncher::class)->resume('wf_cockpit_field');

    expect($result['started'])->toBeTrue()
        ->and($result['pid'])->toBe(4242)
        ->and(FeatureProjection::query()->where('feature_key', 'FEATURE-099A-COCKPIT-MANIFEST')->value('status'))->toBe('pending');

    Process::assertRan(function ($process) {
        $command = is_array($process->command) ? implode(' ', $process->command) : (string) $process->command;

        return str_contains($command, ' recover ');
    });
    Process::assertRan(function ($process) {
        $command = is_array($process->command) ? implode(' ', $process->command) : (string) $process->command;

        return str_contains($command, 'supervise') && str_contains($command, '--debug-command');
    });
});

it('dispara supervise só com preflight verde e não executa o controlador de verdade', function () {
    cockpitLaunchRoot();
    fakeCleanGit();
    $pidFile = storage_path('app/ralph-supervise.pid');
    if (is_file($pidFile)) {
        unlink($pidFile);
    }

    WorkflowProjection::factory()->create(['workflow_id' => 'wf_cockpit_field']);
    FeatureProjection::factory()->create([
        'workflow_id' => 'wf_cockpit_field',
        'feature_key' => 'FEATURE-099A-COCKPIT-MANIFEST',
        'title' => 'Manifesto e preflight do checkout de campo',
        'status' => 'pending',
        'position' => 1,
    ]);

    $result = app(RalphLauncher::class)->start('wf_cockpit_field');

    expect($result['started'])->toBeTrue()
        ->and($result['pid'])->toBe(4242)
        ->and(json_decode((string) file_get_contents($pidFile), true))->toMatchArray([
            'pid' => 4242,
            'workflow_id' => 'wf_cockpit_field',
        ]);

    Process::assertRan(function ($process) {
        $command = is_array($process->command) ? implode(' ', $process->command) : (string) $process->command;

        return str_contains($command, 'supervise') && str_contains($command, '--debug-command');
    });
});

it('não dispara supervise pela UI quando o preflight bloqueia', function () {
    Process::fake();

    WorkflowProjection::factory()->create(['workflow_id' => 'wf_cockpit_demo']);
    FeatureProjection::factory()->create([
        'workflow_id' => 'wf_cockpit_demo',
        'feature_key' => 'FEATURE-092',
        'status' => 'pending',
    ]);

    Livewire::test(TraceCockpit::class)
        ->call('startRalph')
        ->assertSet('launchNoticeKind', 'blocked');

    Process::assertDidntRun(function ($process) {
        $command = is_array($process->command) ? implode(' ', $process->command) : (string) $process->command;

        return str_contains($command, 'supervise');
    });
});

it('recusa pausar quando o cockpit não tem supervisor próprio', function () {
    cockpitLaunchRoot();
    $pidFile = storage_path('app/ralph-supervise.pid');
    if (is_file($pidFile)) {
        unlink($pidFile);
    }

    $result = app(RalphLauncher::class)->pause('wf_cockpit_field');

    expect($result['stopped'])->toBeFalse()
        ->and($result['reason'])->toBe('cockpit.run.not_running');
});

it('não sinaliza um processo vivo que não é supervise', function () {
    cockpitLaunchRoot();
    file_put_contents(storage_path('app/ralph-supervise.pid'), json_encode([
        'pid' => getmypid(),
        'workflow_id' => 'wf_cockpit_field',
    ], JSON_THROW_ON_ERROR));

    $result = app(RalphLauncher::class)->pause('wf_cockpit_field');

    expect($result['stopped'])->toBeFalse()
        ->and($result['reason'])->toBe('cockpit.run.pause_failed')
        ->and(posix_kill(getmypid(), 0))->toBeTrue();
});

it('não pausa pela UI quando não há supervisor do cockpit', function () {
    Process::fake();
    $pidFile = storage_path('app/ralph-supervise.pid');
    if (is_file($pidFile)) {
        unlink($pidFile);
    }

    WorkflowProjection::factory()->create(['workflow_id' => 'wf_cockpit_demo']);

    Livewire::test(TraceCockpit::class)
        ->call('pauseRalph')
        ->assertSet('launchNoticeKind', 'blocked')
        ->assertSet('launchNotice', 'cockpit.run.not_running');
});

it('mostra Diagnosticar e Retomar orquestrador quando a feature está em recovery', function () {
    cockpitLaunchRoot();
    fakeCleanGit();

    WorkflowProjection::factory()->create(['workflow_id' => 'wf_cockpit_field']);
    FeatureProjection::factory()->create([
        'workflow_id' => 'wf_cockpit_field',
        'feature_key' => 'FEATURE-099A-COCKPIT-MANIFEST',
        'title' => 'Manifesto e preflight do checkout de campo',
        'status' => 'blocked',
        'position' => 1,
    ]);

    Livewire::test(TraceCockpit::class)
        ->assertSee('Diagnosticar')
        ->assertSee('Retomar orquestrador')
        ->assertSee('rt-hero is-lock', false)
        ->assertDontSee('Rodar Ralph')
        ->assertDontSee('approve');
});

it('pinta o HUD de ok quando a fila está pronta', function () {
    cockpitLaunchRoot();
    fakeCleanGit();

    WorkflowProjection::factory()->create([
        'workflow_id' => 'wf_cockpit_field',
        'health' => 'ok',
    ]);
    FeatureProjection::factory()->create([
        'workflow_id' => 'wf_cockpit_field',
        'feature_key' => 'FEATURE-099A-COCKPIT-MANIFEST',
        'title' => 'Manifesto e preflight do checkout de campo',
        'status' => 'pending',
        'position' => 1,
    ]);

    Livewire::test(TraceCockpit::class)
        ->assertSee('rt-hero is-ok', false)
        ->assertSee('Rodar Ralph');
});

it('limpa aviso de debug falho enquanto o supervisor está rodando', function () {
    cockpitLaunchRoot();
    fakeCleanGit();

    WorkflowProjection::factory()->create([
        'workflow_id' => 'wf_cockpit_field',
        'health' => 'ok',
        'cursor_feature_key' => 'FEATURE-099A-COCKPIT-MANIFEST',
    ]);
    FeatureProjection::factory()->create([
        'workflow_id' => 'wf_cockpit_field',
        'feature_key' => 'FEATURE-099A-COCKPIT-MANIFEST',
        'title' => 'Manifesto e preflight do checkout de campo',
        'status' => 'running',
        'position' => 1,
    ]);

    file_put_contents(storage_path('app/ralph-supervise.pid'), json_encode([
        'pid' => getmypid(),
        'workflow_id' => 'wf_cockpit_field',
    ], JSON_THROW_ON_ERROR));

    Livewire::test(TraceCockpit::class)
        ->set('launchNotice', 'cockpit.run.debug_failed')
        ->set('launchNoticeKind', 'blocked')
        ->set('diagnosis', [
            'incident_id' => 'INC-COCKPIT-ORCH-001',
            'symptom' => 'Diagnóstico obsoleto do ciclo anterior.',
            'root_cause' => 'Causa antiga.',
            'correction_plan' => 'Plano antigo.',
            'errors' => [],
        ])
        ->assertDontSee('systematic debugging não verificou')
        ->assertDontSee('Diagnóstico obsoleto do ciclo anterior.')
        ->assertSee('Já existe um supervisor ativo neste checkout.');
});
