<?php

namespace Database\Factories;

use App\Models\KnowledgeItem;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<KnowledgeItem>
 */
class KnowledgeItemFactory extends Factory
{
    public function definition(): array
    {
        return [
            'item_key' => 'CUR-2026-'.$this->faker->unique()->numerify('####'),
            'workflow_id' => 'wf_demo',
            'title' => $this->faker->sentence(5),
            'subtitle' => 'pending',
            'status' => 'pending',
        ];
    }
}
