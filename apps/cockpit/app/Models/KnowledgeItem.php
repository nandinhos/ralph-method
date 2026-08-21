<?php

namespace App\Models;

use Database\Factories\KnowledgeItemFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

#[Fillable([
    'item_key',
    'workflow_id',
    'feature_key',
    'title',
    'subtitle',
    'status',
])]
class KnowledgeItem extends Model
{
    /** @use HasFactory<KnowledgeItemFactory> */
    use HasFactory;
}
