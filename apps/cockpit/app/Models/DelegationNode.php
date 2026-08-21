<?php

namespace App\Models;

use Database\Factories\DelegationNodeFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

#[Fillable([
    'workflow_id',
    'role',
    'label',
    'detail',
    'state',
    'position',
])]
class DelegationNode extends Model
{
    /** @use HasFactory<DelegationNodeFactory> */
    use HasFactory;

    protected function casts(): array
    {
        return [
            'position' => 'integer',
        ];
    }
}
