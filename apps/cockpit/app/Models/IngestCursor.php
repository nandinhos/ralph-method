<?php

namespace App\Models;

use Database\Factories\IngestCursorFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

#[Fillable([
    'source_key',
    'byte_offset',
    'last_hash',
])]
class IngestCursor extends Model
{
    /** @use HasFactory<IngestCursorFactory> */
    use HasFactory;

    protected function casts(): array
    {
        return [
            'byte_offset' => 'integer',
        ];
    }
}
