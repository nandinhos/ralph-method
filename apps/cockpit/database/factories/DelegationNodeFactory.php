<?php

namespace Database\Factories;

use App\Models\DelegationNode;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<DelegationNode>
 */
class DelegationNodeFactory extends Factory
{
    public function definition(): array
    {
        return [
            'workflow_id' => 'wf_demo',
            'role' => 'root',
            'label' => 'ralph-control',
            'detail' => 'autoridade',
            'state' => 'root',
            'position' => 0,
        ];
    }
}
