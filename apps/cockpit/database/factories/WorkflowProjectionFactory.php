<?php

namespace Database\Factories;

use App\Models\WorkflowProjection;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<WorkflowProjection>
 */
class WorkflowProjectionFactory extends Factory
{
    public function definition(): array
    {
        return [
            'workflow_id' => 'wf_'.$this->faker->unique()->slug(2),
            'health' => 'ok',
            'state' => 'running',
            'progress_percent' => 40,
            'engine' => 'cursor',
            'attempt' => 1,
            'recovery_count' => 0,
        ];
    }
}
