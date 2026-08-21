<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('timeline_events', function (Blueprint $table) {
            $table->id();
            $table->string('event_key', 190)->unique();
            $table->string('source', 32);
            $table->string('workflow_id', 160)->index();
            $table->string('feature_key', 160)->nullable();
            $table->string('kind', 32)->default('events');
            $table->string('name', 160);
            $table->string('detail', 2000)->nullable();
            $table->string('engine', 80)->nullable();
            $table->timestamp('occurred_at')->nullable()->index();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('timeline_events');
    }
};
