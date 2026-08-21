<?php

namespace App\Console\Commands;

use App\Ralph\RalphIngestor;
use Illuminate\Console\Attributes\Description;
use Illuminate\Console\Attributes\Signature;
use Illuminate\Console\Command;

#[Signature('ralph:ingest {--follow : Continuar lendo os JSONL} {--rebuild : Apagar a projeção e reler} {--no-broadcast : Não emitir Reverb}')]
#[Description('Projeta o runtime do Ralph Method no read-model do cockpit')]
class IngestRalph extends Command
{
    public function handle(RalphIngestor $ingestor): int
    {
        $broadcast = ! $this->option('no-broadcast');

        if ($this->option('rebuild')) {
            $changed = $ingestor->rebuild();
            if ($broadcast) {
                $ingestor->broadcast($changed);
            }
            $this->info('rebuild: '.count($changed).' workflow(s)');
        }

        do {
            $changed = $ingestor->tick();
            if ($changed !== [] && $broadcast) {
                $ingestor->broadcast($changed);
            }
            if ($this->option('follow')) {
                sleep(max(1, (int) config('ralph.follow_sleep_seconds')));
            }
        } while ($this->option('follow'));

        $this->info('tick: '.count($changed).' workflow(s)');

        return self::SUCCESS;
    }
}
