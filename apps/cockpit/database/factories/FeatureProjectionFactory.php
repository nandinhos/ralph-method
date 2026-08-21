<?php

namespace Database\Factories;

use App\Models\FeatureProjection;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<FeatureProjection>
 */
class FeatureProjectionFactory extends Factory
{
    public function definition(): array
    {
        return [
            'workflow_id' => 'wf_demo',
            'feature_key' => 'FEATURE-'.$this->faker->unique()->numerify('###'),
            'title' => $this->faker->sentence(4),
            'position' => 1,
            'status' => 'pending',
            'engine' => 'cursor',
        ];
    }
}
