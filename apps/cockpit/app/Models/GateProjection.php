<?php

namespace App\Models;

use Database\Factories\GateProjectionFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

#[Fillable([
    'workflow_id',
    'feature_key',
    'gate_key',
    'status',
    'detail',
])]
class GateProjection extends Model
{
    /** @use HasFactory<GateProjectionFactory> */
    use HasFactory;
}
