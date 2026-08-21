<?php

namespace App\Models;

use Database\Factories\WorkflowProjectionFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable([
    'workflow_id',
    'branch',
    'health',
    'state',
    'cursor_feature_key',
    'progress_percent',
    'engine',
    'attempt',
    'recovery_count',
    'started_at',
    'last_event_at',
    'monitor_payload',
])]
class WorkflowProjection extends Model
{
    /** @use HasFactory<WorkflowProjectionFactory> */
    use HasFactory;

    protected function casts(): array
    {
        return [
            'progress_percent' => 'integer',
            'attempt' => 'integer',
            'recovery_count' => 'integer',
            'started_at' => 'datetime',
            'last_event_at' => 'datetime',
            'monitor_payload' => 'array',
        ];
    }

    public function features(): HasMany
    {
        return $this->hasMany(FeatureProjection::class, 'workflow_id', 'workflow_id')->orderBy('position');
    }

    public function timeline(): HasMany
    {
        return $this->hasMany(TimelineEvent::class, 'workflow_id', 'workflow_id')->orderByDesc('occurred_at');
    }

    public function knowledge(): HasMany
    {
        return $this->hasMany(KnowledgeItem::class, 'workflow_id', 'workflow_id');
    }

    public function delegations(): HasMany
    {
        return $this->hasMany(DelegationNode::class, 'workflow_id', 'workflow_id')->orderBy('position');
    }
}
