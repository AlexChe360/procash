@props(['name', 'label', 'value' => '', 'type' => 'text', 'required' => true])
<div class="form-field"><label for="{{ $name }}">{{ $label }}</label>
@if($type === 'textarea')<textarea id="{{ $name }}" name="{{ $name }}" @required($required) {{ $attributes }}>{{ old($name, $value) }}</textarea>
@else<input id="{{ $name }}" name="{{ $name }}" type="{{ $type }}" value="{{ $type === 'password' ? '' : old($name, $value) }}" @required($required) {{ $attributes }}>@endif
@error($name)<span class="field-error" role="alert">{{ $message }}</span>@enderror</div>
