<?php

namespace Database\Factories;

use App\Models\IngestCursor;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<IngestCursor>
 */
class IngestCursorFactory extends Factory
{
    public function definition(): array
    {
        return [
            'source_key' => $this->faker->unique()->word(),
            'byte_offset' => 0,
        ];
    }
}
