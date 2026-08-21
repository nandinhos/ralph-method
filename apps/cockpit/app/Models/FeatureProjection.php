<?php

namespace App\Models;

use Database\Factories\FeatureProjectionFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable([
    'workflow_id',
    'feature_key',
    'title',
    'position',
    'status',
    'engine',
    'attempt',
    'duration_seconds',
])]
class FeatureProjection extends Model
{
    /** @use HasFactory<FeatureProjectionFactory> */
    use HasFactory;

    protected function casts(): array
    {
        return [
            'position' => 'integer',
            'attempt' => 'integer',
            'duration_seconds' => 'integer',
        ];
    }

    public function gates(): HasMany
    {
        return $this->hasMany(GateProjection::class, 'feature_key', 'feature_key')
            ->where('workflow_id', $this->workflow_id);
    }
}
