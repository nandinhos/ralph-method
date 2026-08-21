@props(['runtime'])

<div class="rt-chips">
    @foreach ($runtime as $chip)
        <span class="rt-chip {{ $chip['ok'] ? 'is-ok' : 'is-off' }}">
            <strong>{{ __('cockpit.runtime.'.$chip['key']) }}</strong>
            {{ $chip['value'] }}
        </span>
    @endforeach
</div>
