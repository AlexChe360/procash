@if ($paginator->hasPages())
<nav class="pc-actions" aria-label="Страницы списка">
    @if ($paginator->onFirstPage())
        <span aria-disabled="true">Назад</span>
    @else
        <a class="secondary-button" rel="prev" href="{{ $paginator->previousPageUrl() }}">Назад</a>
    @endif
    <span>Страница {{ $paginator->currentPage() }}</span>
    @if ($paginator->hasMorePages())
        <a class="secondary-button" rel="next" href="{{ $paginator->nextPageUrl() }}">Далее</a>
    @else
        <span aria-disabled="true">Далее</span>
    @endif
</nav>
@endif
