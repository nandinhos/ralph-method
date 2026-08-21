#!/usr/bin/env php
<?php

declare(strict_types=1);

/**
 * ralph-time-report.php — relatório de tempo decorrido por feature, agrupado
 * por onda (workflow) e phase (source_phase).
 *
 * Backlog BL-0005 (métricas de processo): medir, a partir do ledger
 * (events.jsonl), quanto tempo cada feature levou e em que fases esse tempo
 * foi gasto — implementação, gates, debugging, esperas — para identificar
 * pontos de melhoria do processo. Somente leitura: não muta ledger, não grava
 * estado global, não toca em .spec/.
 *
 * Uso:
 *   php bin/ralph-time-report.php \
 *     --ledger /caminho/.git/ralph-control/events.jsonl \
 *     [--workflow wf_...] [--format json|md] [--out arquivo]
 *
 * Saída (stdout ou --out): por feature — duração total, tempo em
 * implementação (claim→block.finished), em gates (block.finished→approved),
 * em debugging (debugging.started→debugging.verified), número de attempts,
 * gates aprovados/rejeitados e first/last timestamps; agregado por
 * workflow_id (onda) e source_phase (phase da fila).
 */

/** @return array<string, mixed> */
function parseArgs(array $argv): array
{
    $options = [];
    for ($index = 1; $index < count($argv); $index++) {
        $argument = $argv[$index];
        if (! str_starts_with($argument, '--')) {
            fwrite(STDERR, "argumento inesperado: {$argument}\n");
            exit(2);
        }
        $name = substr($argument, 2);
        $value = $argv[++$index] ?? null;
        if ($value === null || str_starts_with($value, '--')) {
            fwrite(STDERR, "--{$name} exige valor\n");
            exit(2);
        }
        $options[$name] = $value;
    }

    return $options;
}

function requiredOption(array $options, string $name): string
{
    $value = trim((string) ($options[$name] ?? ''));
    if ($value === '') {
        fwrite(STDERR, "--{$name} obrigatório\n");
        exit(2);
    }

    return $value;
}

/** @return list<array<string, mixed>> */
function readLedger(string $path): array
{
    if (! is_file($path)) {
        fwrite(STDERR, "ledger não encontrado: {$path}\n");
        exit(1);
    }
    $events = [];
    $handle = fopen($path, 'rb');
    if ($handle === false) {
        fwrite(STDERR, "não foi possível abrir o ledger: {$path}\n");
        exit(1);
    }
    while (($line = fgets($handle)) !== false) {
        $line = trim($line);
        if ($line === '') {
            continue;
        }
        $event = json_decode($line, true, 512, JSON_THROW_ON_ERROR);
        if (is_array($event)) {
            $events[] = $event;
        }
    }
    fclose($handle);

    return $events;
}

/** @return array<string, mixed> */
function parseIso(string $iso): array
{
    $epoch = strtotime($iso);
    if ($epoch === false) {
        return ['epoch' => null, 'iso' => $iso];
    }

    return ['epoch' => $epoch, 'iso' => $iso];
}

function formatDuration(int $seconds): string
{
    if ($seconds < 0) {
        return '-';
    }
    $hours = intdiv($seconds, 3600);
    $minutes = intdiv($seconds % 3600, 60);
    $secs = $seconds % 60;

    if ($hours > 0) {
        return sprintf('%dh %02dm %02ds', $hours, $minutes, $secs);
    }
    if ($minutes > 0) {
        return sprintf('%dm %02ds', $minutes, $secs);
    }

    return sprintf('%ds', $secs);
}

/** @param list<array<string, mixed>> $events @return array<string, array<string, mixed>> */
function projectFeatures(array $events, string $workflowFilter): array
{
    $features = [];
    foreach ($events as $event) {
        $workflow = (string) ($event['workflow_id'] ?? '');
        if ($workflowFilter !== '' && $workflow !== $workflowFilter) {
            continue;
        }
        $key = (string) ($event['feature_key'] ?? '');
        if ($key === '') {
            continue;
        }
        $type = (string) ($event['type'] ?? '');
        // eventos de controle interno (workflow.*) não pertencem a uma feature
        if (str_starts_with($type, 'workflow.')) {
            continue;
        }
        $type = (string) ($event['type'] ?? '');
        $timestamp = (string) ($event['timestamp'] ?? '');
        $parsed = parseIso($timestamp);
        $facts = is_array($event['facts'] ?? null) ? $event['facts'] : [];
        $features[$key] ??= [
            'feature_key' => $key,
            'workflow_id' => $workflow,
            'attempts' => 0,
            'first_event_at' => $parsed,
            'last_event_at' => $parsed,
            'claimed_at' => null,
            'released_at' => null,
            'block_finished_at' => null,
            'approved_at' => null,
            'debugging_starts' => 0,
            'debugging_start_at' => null,
            'debugging_end_at' => null,
            'gates_passed' => [],
            'gates_rejected' => [],
            'implementation_seconds' => 0,
            'gates_seconds' => 0,
            'debugging_seconds' => 0,
            'other_seconds' => 0,
            'status' => 'in_progress',
            'source_phase' => null,
        ];
        $feature = &$features[$key];
        $epoch = $parsed['epoch'];
        if ($epoch !== null) {
            if ($feature['first_event_at']['epoch'] === null
                || $epoch < $feature['first_event_at']['epoch']) {
                $feature['first_event_at'] = $parsed;
            }
            if ($feature['last_event_at']['epoch'] === null
                || $epoch > $feature['last_event_at']['epoch']) {
                $feature['last_event_at'] = $parsed;
            }
        }
        switch ($type) {
            case 'feature.claimed':
                $feature['attempts']++;
                $feature['claimed_at'] = $parsed;
                break;
            case 'block.finished':
                $feature['block_finished_at'] = $parsed;
                if (($facts['exit_code'] ?? null) !== 0) {
                    $feature['status'] = 'block_failed';
                }
                break;
            case 'gate.passed':
                $feature['gates_passed'][] = (string) ($facts['gate'] ?? '?');
                break;
            case 'gate.rejected':
                $feature['gates_rejected'][] = (string) ($facts['gate'] ?? '?');
                break;
            case 'debugging.started':
                $feature['debugging_starts']++;
                $feature['debugging_start_at'] = $parsed;
                $feature['status'] = 'debugging';
                break;
            case 'debugging.verified':
                $feature['debugging_end_at'] = $parsed;
                break;
            case 'feature.approved':
                $feature['approved_at'] = $parsed;
                $feature['status'] = 'approved';
                break;
            case 'feature.released':
                $feature['released_at'] = $parsed;
                $feature['status'] = 'released';
                break;
            case 'feature.advanced':
                $feature['status'] = 'released';
                break;
            case 'recovery.required':
                $feature['status'] = 'recovery_required';
                break;
            case 'recovery.resolved':
                if (($feature['status'] ?? '') === 'recovery_required') {
                    $feature['status'] = 'recovering';
                }
                break;
        }
        unset($feature);
    }

    // Ordena por first_event_at e computa as durações por janela.
    uasort($features, static fn (array $a, array $b): int => ($a['first_event_at']['epoch'] ?? 0) <=> ($b['first_event_at']['epoch'] ?? 0));
    foreach ($features as $key => &$feature) {
        $total = 0;
        $releasedEpoch = $feature['released_at']['epoch'] ?? null;
        $firstEpoch = $feature['first_event_at']['epoch'] ?? null;
        $lastEpoch = $feature['last_event_at']['epoch'] ?? null;
        if ($releasedEpoch !== null && $firstEpoch !== null) {
            $total = $releasedEpoch - $firstEpoch;
        } elseif ($lastEpoch !== null && $firstEpoch !== null) {
            $total = $lastEpoch - $firstEpoch;
        }
        $feature['total_seconds'] = $total;
        $feature['total_duration'] = formatDuration($total);

        // Coleciona timestamps por tipo e attempt (para parear claim→finish do
        // MESMO attempt; claims órfãos sem finish não viram janela de impl).
        $claims = [];
        $finishes = [];
        $dbgStarts = [];
        $dbgEnds = [];
        foreach ($events as $event) {
            if ((string) ($event['feature_key'] ?? '') !== $key) {
                continue;
            }
            $type = (string) ($event['type'] ?? '');
            $ep = parseIso((string) ($event['timestamp'] ?? ''))['epoch'];
            if ($ep === null) {
                continue;
            }
            $attempt = (int) ($event['attempt'] ?? 0);
            switch ($type) {
                case 'feature.claimed': $claims[$attempt] = $ep; break;
                case 'block.finished': $finishes[$attempt] = $ep; break;
                case 'debugging.started': $dbgStarts[] = $ep; break;
                case 'debugging.verified': $dbgEnds[] = $ep; break;
            }
        }
        ksort($claims);
        ksort($finishes);
        sort($dbgStarts);
        sort($dbgEnds);

        // Janelas de debugging: started→verified (pares na ordem).
        $debugWindows = [];
        foreach ($dbgStarts as $index => $start) {
            $end = $dbgEnds[$index] ?? null;
            if ($end !== null && $end > $start) {
                $debugWindows[] = ['from' => $start, 'to' => $end];
            }
        }

        // Janelas de implementação: claim→block.finished do mesmo attempt;
        // subtrai debugging que caiu dentro delas (evita dupla contagem).
        $implWindows = [];
        foreach ($claims as $attempt => $claimEpoch) {
            $finishEpoch = $finishes[$attempt] ?? null;
            if ($finishEpoch === null || $finishEpoch <= $claimEpoch) {
                continue; // claim órfão (sem finish) ou janela inválida
            }
            $implWindows[] = ['from' => $claimEpoch, 'to' => $finishEpoch];
        }
        foreach ($implWindows as $index => $window) {
            foreach ($debugWindows as $debug) {
                $overlapFrom = max($window['from'], $debug['from']);
                $overlapTo = min($window['to'], $debug['to']);
                if ($overlapTo > $overlapFrom) {
                    $implWindows[$index]['from'] = $overlapTo;
                }
            }
        }

        // Gates: do último block.finished até a aprovação/release.
        $gateWindows = [];
        $lastFinish = $finishes === [] ? null : max($finishes);
        $approval = $feature['approved_at']['epoch'] ?? $feature['released_at']['epoch'] ?? null;
        if ($lastFinish !== null && $approval !== null && $approval > $lastFinish) {
            $gateWindows[] = ['from' => $lastFinish, 'to' => $approval];
        }

        $sum = static fn (array $windows): int => array_sum(array_map(
            static fn (array $w): int => $w['to'] - $w['from'],
            $windows,
        ));
        $feature['implementation_seconds'] = $sum($implWindows);
        $feature['gates_seconds'] = $sum($gateWindows);
        $feature['debugging_seconds'] = $sum($debugWindows);

        // Outros/esperas = total - (impl + gates + debug), nunca negativo.
        $coveredTotal = $feature['implementation_seconds'] + $feature['gates_seconds'] + $feature['debugging_seconds'];
        $feature['other_seconds'] = max(0, $total - $coveredTotal);
        $feature['implementation_duration'] = formatDuration($feature['implementation_seconds']);
        $feature['gates_duration'] = formatDuration($feature['gates_seconds']);
        $feature['debugging_duration'] = formatDuration($feature['debugging_seconds']);
        $feature['other_duration'] = formatDuration($feature['other_seconds']);
        unset($feature);
    }

    return $features;
}

/** @param array<string, array<string, mixed>> $features @return array<string, mixed> */
function aggregateByWorkflow(array $features): array
{
    $byWorkflow = [];
    foreach ($features as $feature) {
        $workflow = $feature['workflow_id'] !== '' ? $feature['workflow_id'] : '(sem workflow)';
        $byWorkflow[$workflow] ??= [
            'workflow_id' => $workflow,
            'features' => 0,
            'released' => 0,
            'total_seconds' => 0,
            'implementation_seconds' => 0,
            'gates_seconds' => 0,
            'debugging_seconds' => 0,
            'other_seconds' => 0,
            'attempts' => 0,
            'gates_passed' => 0,
            'gates_rejected' => 0,
        ];
        $bucket = &$byWorkflow[$workflow];
        $bucket['features']++;
        $bucket['released'] += ($feature['status'] === 'released') ? 1 : 0;
        $bucket['total_seconds'] += $feature['total_seconds'];
        $bucket['implementation_seconds'] += $feature['implementation_seconds'];
        $bucket['gates_seconds'] += $feature['gates_seconds'];
        $bucket['debugging_seconds'] += $feature['debugging_seconds'];
        $bucket['other_seconds'] += $feature['other_seconds'];
        $bucket['attempts'] += $feature['attempts'];
        $bucket['gates_passed'] += count($feature['gates_passed']);
        $bucket['gates_rejected'] += count($feature['gates_rejected']);
        unset($bucket);
    }

    return array_values($byWorkflow);
}

/** @param array<string, array<string, mixed>> $features @return array<string, mixed> */
function buildReport(array $features, string $workflowFilter): array
{
    return [
        'schema_version' => '1.0.0',
        'generated_at' => gmdate('c'),
        'workflow_filter' => $workflowFilter,
        'feature_count' => count($features),
        'workflows' => aggregateByWorkflow($features),
        'features' => array_values($features),
    ];
}

function renderMarkdown(array $report): string
{
    $out = [];
    $out[] = '# Relatório de tempo do Ralph Method';
    $out[] = '';
    $out[] = 'Gerado em: '.$report['generated_at'];
    $out[] = '';
    $out[] = '## Resumo por onda (workflow)';
    $out[] = '';
    $out[] = '| Onda | Features | Liberadas | Tempo total | Implementação | Gates | Debugging | Outros/esperas | Attempts | Gates ✅ | Gates ❌ |';
    $out[] = '|---|---|---|---|---|---|---|---|---|---|---|';
    foreach ($report['workflows'] as $workflow) {
        $out[] = sprintf(
            '| %s | %d | %d | %s | %s | %s | %s | %s | %d | %d | %d |',
            $workflow['workflow_id'],
            $workflow['features'],
            $workflow['released'],
            formatDuration($workflow['total_seconds']),
            formatDuration($workflow['implementation_seconds']),
            formatDuration($workflow['gates_seconds']),
            formatDuration($workflow['debugging_seconds']),
            formatDuration($workflow['other_seconds']),
            $workflow['attempts'],
            $workflow['gates_passed'],
            $workflow['gates_rejected'],
        );
    }
    $out[] = '';
    $out[] = '## Por feature';
    $out[] = '';
    $out[] = '| Feature | Phase | Status | Attempts | Total | Implementação | Gates | Debugging | Outros | Gates ✅ | Gates ❌ |';
    $out[] = '|---|---|---|---|---|---|---|---|---|---|---|';
    foreach ($report['features'] as $feature) {
        $out[] = sprintf(
            '| %s | %s | %s | %d | %s | %s | %s | %s | %s | %d | %d |',
            $feature['feature_key'],
            (string) ($feature['source_phase'] ?? '-'),
            $feature['status'],
            $feature['attempts'],
            $feature['total_duration'],
            $feature['implementation_duration'],
            $feature['gates_duration'],
            $feature['debugging_duration'],
            $feature['other_duration'],
            count($feature['gates_passed']),
            count($feature['gates_rejected']),
        );
    }
    $out[] = '';

    return implode("\n", $out);
}

$options = parseArgs($argv);
$ledgerPath = requiredOption($options, 'ledger');
$workflowFilter = trim((string) ($options['workflow'] ?? ''));
$format = trim((string) ($options['format'] ?? 'json'));
$outFile = trim((string) ($options['out'] ?? ''));

$events = readLedger($ledgerPath);
$features = projectFeatures($events, $workflowFilter);
$report = buildReport($features, $workflowFilter);

$output = $format === 'md' ? renderMarkdown($report) : json_encode($report, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
if ($outFile !== '') {
    if (file_put_contents($outFile, $output."\n") === false) {
        fwrite(STDERR, "não foi possível gravar o relatório: {$outFile}\n");
        exit(1);
    }
    echo "relatório gravado em: {$outFile}\n";
} else {
    echo $output."\n";
}
exit(0);
