<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('delegation_nodes', function (Blueprint $table) {
            $table->id();
            $table->string('workflow_id', 160);
            $table->string('role', 32);
            $table->string('label', 160);
            $table->string('detail', 500)->nullable();
            $table->string('state', 32)->default('ok');
            $table->unsignedInteger('position')->default(0);
            $table->timestamps();
            $table->unique(['workflow_id', 'role', 'label']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('delegation_nodes');
    }
};
