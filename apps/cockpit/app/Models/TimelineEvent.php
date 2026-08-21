<?php

namespace App\Models;

use Database\Factories\TimelineEventFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

#[Fillable([
    'event_key',
    'source',
    'workflow_id',
    'feature_key',
    'kind',
    'name',
    'detail',
    'engine',
    'occurred_at',
])]
class TimelineEvent extends Model
{
    /** @use HasFactory<TimelineEventFactory> */
    use HasFactory;

    protected function casts(): array
    {
        return [
            'occurred_at' => 'datetime',
        ];
    }
}
