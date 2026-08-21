<?php

namespace Database\Factories;

use App\Models\TimelineEvent;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<TimelineEvent>
 */
class TimelineEventFactory extends Factory
{
    public function definition(): array
    {
        return [
            'event_key' => $this->faker->unique()->uuid(),
            'source' => 'ledger',
            'workflow_id' => 'wf_demo',
            'kind' => 'events',
            'name' => 'feature.claimed',
            'detail' => 'lease adquirido',
            'occurred_at' => now(),
        ];
    }
}
