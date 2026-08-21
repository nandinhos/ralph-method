<?php

use Illuminate\Support\Facades\Broadcast;

Broadcast::channel('ralph.cockpit.{workflowId}', fn () => true);
