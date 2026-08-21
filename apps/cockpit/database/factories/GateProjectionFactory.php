<?php

namespace Database\Factories;

use App\Models\GateProjection;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<GateProjection>
 */
class GateProjectionFactory extends Factory
{
    public function definition(): array
    {
        return [
            'workflow_id' => 'wf_demo',
            'feature_key' => 'FEATURE-001',
            'gate_key' => 'quality',
            'status' => 'pending',
        ];
    }
}
