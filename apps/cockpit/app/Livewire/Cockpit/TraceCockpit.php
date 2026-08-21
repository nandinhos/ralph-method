<?php

namespace App\Livewire\Cockpit;

use App\Models\DelegationNode;
use App\Models\FeatureProjection;
use App\Models\GateProjection;
use App\Models\KnowledgeItem;
use App\Models\TimelineEvent;
use App\Models\WorkflowProjection;
use App\Ralph\CockpitHealth;
use App\Ralph\CockpitProgress;
use App\Ralph\CockpitTone;
use App\Ralph\GateCatalog;
use App\Ralph\RalphLauncher;
use Livewire\Attributes\Layout;
use Livewire\Component;
use Throwable;

#[Layout('layouts.cockpit')]
class TraceCockpit extends Component
{
    public string $filter = 'all';

    public string $workflowId = '';

    public string $launchNotice = '';

    public string $launchNoticeKind = '';

    /**
     * @var array{incident_id?: string, symptom?: string, root_cause?: string, correction_plan?: string, errors?: list<string>}
     */
    public array $diagnosis = [];

    public function mount(): void
    {
        $this->workflowId = (string) (WorkflowProjection::query()
            ->orderByDesc('last_event_at')
            ->value('workflow_id') ?? '');
    }

    /**
     * @return array<string, string>
     */
    public function getListeners(): array
    {
        if ($this->workflowId === '') {
            return [];
        }

        return [
            "echo:ralph.cockpit.{$this->workflowId},.cockpit.updated" => 'onCockpitUpdated',
        ];
    }

    public function setFilter(string $filter): void
    {
        $this->filter = in_array($filter, ['all', 'events', 'gates'], true) ? $filter : 'all';
    }

    public function onCockpitUpdated(): void
    {
        $this->dispatch('$refresh');
    }

    public function refreshSnapshot(): void
    {
        $this->dispatch('$refresh');
    }

    public function startRalph(): void
    {
        try {
            $result = app(RalphLauncher::class)->start($this->workflowId);
            $this->launchNotice = $result['reason'];
            $this->launchNoticeKind = $result['started'] ? 'ok' : 'blocked';
            if ($result['started']) {
                $this->diagnosis = [];
            }
        } catch (Throwable) {
            $this->launchNotice = 'cockpit.run.start_failed';
            $this->launchNoticeKind = 'blocked';
        }
    }

    public function debugRalph(): void
    {
        try {
            $result = app(RalphLauncher::class)->debug($this->workflowId);
            $this->launchNotice = $result['reason'];
            $this->launchNoticeKind = $result['debugged'] ? 'ok' : 'blocked';
            $this->diagnosis = $result['report'];
        } catch (Throwable) {
            $this->launchNotice = 'cockpit.run.debug_failed';
            $this->launchNoticeKind = 'blocked';
        }
    }

    public function resumeRalph(): void
    {
        try {
            $result = app(RalphLauncher::class)->resume($this->workflowId);
            $this->launchNotice = $result['reason'];
            $this->launchNoticeKind = $result['started'] ? 'ok' : 'blocked';
            if ($result['started']) {
                $this->diagnosis = [];
            }
        } catch (Throwable) {
            $this->launchNotice = 'cockpit.run.start_failed';
            $this->launchNoticeKind = 'blocked';
        }
    }

    public function pauseRalph(): void
    {
        try {
            $result = app(RalphLauncher::class)->pause($this->workflowId);
            $this->launchNotice = $result['reason'];
            $this->launchNoticeKind = $result['stopped'] ? 'ok' : 'blocked';
        } catch (Throwable) {
            $this->launchNotice = 'cockpit.run.pause_failed';
            $this->launchNoticeKind = 'blocked';
        }
    }

    public function render()
    {
        $workflow = $this->workflowId
            ? WorkflowProjection::query()->where('workflow_id', $this->workflowId)->first()
            : null;

        $features = $workflow
            ? FeatureProjection::query()
                ->where('workflow_id', $workflow->workflow_id)
                ->orderBy('position')
                ->get()
            : collect();

        $gates = $workflow
            ? GateProjection::query()
                ->where('workflow_id', $workflow->workflow_id)
                ->get()
                ->groupBy('feature_key')
            : collect();

        $events = $workflow
            ? TimelineEvent::query()
                ->where('workflow_id', $workflow->workflow_id)
                ->where('name', '!=', 'command.heartbeat')
                ->when($this->filter === 'events', fn ($query) => $query->where('kind', 'events'))
                ->when($this->filter === 'gates', fn ($query) => $query->where('kind', 'gates'))
                ->orderByDesc('occurred_at')
                ->limit(40)
                ->get()
            : collect();

        $knowledge = KnowledgeItem::query()->latest('created_at')->limit(8)->get();

        $delegations = $workflow
            ? DelegationNode::query()->where('workflow_id', $workflow->workflow_id)->orderBy('position')->get()
            : collect();

        $current = $features->firstWhere('feature_key', $workflow?->cursor_feature_key)
            ?? $features->firstWhere('status', 'running')
            ?? $features->first(fn ($feature) => ! in_array($feature->status, ['released', 'approved'], true));

        $launch = app(RalphLauncher::class)->decision($this->workflowId);
        $this->syncLaunchPresentation($launch);

        $hud = $workflow
            ? app(CockpitProgress::class)->forHud($workflow, $features, $gates)
            : ['percent' => 0, 'label' => 'workflow', 'detail' => '', 'feature_slot_percent' => 0, 'active' => false];

        return view('livewire.cockpit.trace-cockpit', [
            'workflow' => $workflow,
            'features' => $features,
            'gates' => $gates,
            'events' => $events,
            'knowledge' => $knowledge,
            'delegations' => $delegations,
            'current' => $current,
            'gateKeys' => GateCatalog::KEYS,
            'launch' => $launch,
            'hud' => $hud,
            'tone' => app(CockpitTone::class)->for($launch, $workflow),
            'runtime' => app(CockpitHealth::class)->snapshot(),
        ]);
    }

    /**
     * @param  array{ready?: bool, reason?: string, running?: bool, pauseable?: bool, cursor_state?: ?string, can_recover?: bool, can_debug?: bool, can_resume?: bool}  $launch
     */
    private function syncLaunchPresentation(array $launch): void
    {
        if ($launch['running'] ?? false) {
            if ($this->launchNoticeKind === 'blocked') {
                $this->launchNotice = '';
                $this->launchNoticeKind = '';
            }
            $this->diagnosis = [];

            return;
        }

        if ($this->launchIsStuck($launch)) {
            if (($this->diagnosis['symptom'] ?? '') === '' && $this->workflowId !== '') {
                $this->diagnosis = app(RalphLauncher::class)->latestDiagnosis($this->workflowId);
            }

            return;
        }

        if ($this->launchNoticeKind === 'blocked' && str_starts_with($this->launchNotice, 'cockpit.run.debug')) {
            $this->launchNotice = '';
            $this->launchNoticeKind = '';
        }

        $this->diagnosis = [];
    }

    /**
     * @param  array{ready?: bool, reason?: string, running?: bool, pauseable?: bool, cursor_state?: ?string, can_recover?: bool, can_debug?: bool, can_resume?: bool}  $launch
     */
    private function launchIsStuck(array $launch): bool
    {
        return ($launch['can_debug'] ?? false)
            || ($launch['can_recover'] ?? false)
            || ($launch['can_resume'] ?? false)
            || in_array($launch['cursor_state'] ?? null, ['recovery_required', 'blocked', 'debugging_required'], true);
    }
}
