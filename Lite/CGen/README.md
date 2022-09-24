# Brief Internals of YATT::Lite::CGen::Perl

## Template (Widget)

```html
<!yatt:args a=text b=text>

**Toplevel**

&yatt:a;

<yatt:foo -- x, y, z, w is assignments --
  x="...assignment to text..."
  z="... to value"
  w="... to list"
>

  **Toplevel (in body closure)**

  <yatt:bar x="foo &yatt:a; bar">
    <:yatt:y>... to html</:yatt:y>

    **Toplevel (in body closure)**

  </yatt:bar>

<:yatt:y/>
  ... to html
</yatt:foo>
```

```html
<!yatt:widget foo x=text y=html z=value w=list body=[code]>

<!yatt:widget bar x=text y=html z=value w=list body=[code]>

```

※processing instructions `<?perl= ... ?>` are omitted in this doc.

### How toplevel code generator works - simplified version of `as_print()`

`as_print()` scans current tokens in `$self->{curtoks}` and basically generates a sequence of statements which mostly are print statements.

- Most tokens are converted to **printable expressions** and queued to `@queue`.
- Also token handlers can generate **general statements** which are represented by scalar reference that directly goes to `@result`.
- Then if current token contains newline, `@queue` is flushed and they go to final code fragment list `@result`;
- Finally, every generated codes in `@result` are joined to a result string.

```perl
sub as_print {
  my ($self) = @_;
  my (@result, @queue);
  my sub flush {
    push @result, q{print $CON (}.join(", ", @queue). q{);} if @queue;
    undef @queue;
  }
  while (@{$self->{curtoks}}) {
    my $node = @{$self->{curtoks}};
    if (not ref $node) {
      push @queue, qtext($node);
      flush() if $node =~ /\n/;
    }
    else {
      my $handler = $DISPATCH[$node->[0]]; # from_element, from_entity...
      my $expr = $handler->($self, $node);
      if (not defined $expr) {
        push @result, $self->cut_next_newline;
      }
      elsif (ref $expr) {
        flush();
        push @result, "$$expr; ", $self->cut_next_newline;
      }
      else {
        push @queue, $expr;
        flush() if $expr =~ /\n/;
      }
    }
  }
  flush();
  join " ", @result;
}
```



### Corresponding handlers for each node kinds and their appeared contexts

<table border="0" cellspacing="0" cellpadding="0" class="table-1">
<style>
table.table-1 th {text-align: left;}
table.table-1 th.bottom {border-bottom-width: 5px;}
table.table-1 th.right  {border-right-width:  5px;}
</style>
<colgroup>
<col width="140"/>
<col width="80"/>
<col width="90"/>
<col width="181"/>
<col width="201"/>
</colgroup>
<tr class="ro4">
<th colspan="2" rowspan="2" class="bottom right"><p>Context \ Node Kind</p></th>
<th rowspan="2" class="bottom"><p>constant text</p><p>(trusted)</p></th>
<th rowspan="2" class="bottom"><p>element</p><p>(general statement)</p></th>
<th rowspan="2" class="bottom"><p>entity</p><p>(typed replacement)</p></th></tr>
<tr class="ro4"/>
<tr class="ro5">
<th colspan="2" class="right"><p>Toplevel</p><p>(= Output as_print())</p></th><td><p>qtext()</p></td>
<td><p>from_element (invoke)</p></td>
<td rowspan="6"><p>from_entity() </p><p>→ gen_entpath()</p><p>→ as_print()</p></td></tr>
<tr class="ro6">
<th rowspan="5"><p>Assignment (Cast to type)</p><p>/ Composition</p></th>
<th class="right"><p>text</p><p>as_cast_to_text:</p></th>
<td><p>qtext()</p><p>/ gen_as(text)</p></td>
<td><p>?text_from_element</p><p>→ <code>capture {</code><br>from_element<br><code>}</code></p></td></tr>
<tr class="ro6">
<th class="right"><p>html</p><p>as_cast_to_html:</p></th>
<td><p>qtext()</p><p>/ gen_as(text, <b>escaping</b> )</p></td>
<td><p>?text_from_element</p><p>→ <code>capture {</code><br>from_element<br><code>}</code></p></td></tr>
<tr class="ro3">
<th class="right"><p>value</p><p>as_cast_to_scalar:</p></th>
<td><p><code>scalar do {</code>gen_as(list)<code>}</code></p></td>
<td><p>-</p></td></tr>
<tr class="ro3">
<th class="right"><p>list</p><p>as_cast_to_list:</p></th>
<td><p><code>[</code>gen_as(list)<code>]</code></p></td>
<td><p>-</p></td></tr>
<tr class="ro3">
<th class="right"><p>code<br>(widget)</p><p>as_cast_to_code:</p></th>
<td><p><b>escaping</b>, as_print</p></td>
<td><p>from_element (invoke)</p></td></tr>
</table>

### Entity Path Items

YATT entities like `&yatt:foo;` are parsed as a namespace prefix `&yatt`, one or more entity path items `:foo` and terminal `;`.
* Entity path items can start either `:var` or `:call(...)` which can also takes path items as arguments in `(...)`.
  ```
  :var
  :call(...)
  ```


* In entity arguments `(...)`, each startings of path items can also be `(text)`, `(=expr)`, `[array]` and `{hash}`.

  ```
  (text...)
  (=expr...)
  [array...]
  {hash...}
  ```


* After the leading items, arbitrary number of `:prop`, `:invoke(...)`, `[aref]` and `{href}` can follow.

  ```
  〜:prop
  〜:invoke(...)
  〜[aref...]
  〜{href...}
  ```


### Corresponding handlers called from gen_entpath

<table border="0" cellspacing="0" cellpadding="0" class="ta1">
<colgroup>
<col width="111"/>
<col width="111"/>
<col width="128"/>
<col width="181"/>
<col width="407"/>
</colgroup>
<tr class="ro4">
<td><p>path place</p></td>
<td><p>path item kind</p></td>
<td><p>handler</p></td>
<td><p>name kind/var type</p></td>
<td><p>codegen action (pseudo code with JS style template string)</p></td>
</tr>
<tr class="ro4">
<td><p>head</p></td>
<td><p>var</p></td>
<td><p>as_expr_var($name)</p></td>
<td> </td>
<td><p>as_lvalue($var)</p></td>
</tr>
<tr class="ro4">
<td> </td>
<td> </td>
<td> </td>
<td><p>entity</p></td>
<td><p>gen_entcall($name)</p></td>
</tr>
<tr class="ro5">
<td> </td>
<td> </td>
<td> </td>
<td><p>var html</p><p><span class="T2">→ as_expr_var_html</span></p></td>
<td><p>escaping, as_lvalue_html($var)</p></td>
</tr>
<tr class="ro5">
<td> </td>
<td> </td>
<td> </td>
<td><p>var attr</p><p><span class="T2">→ as_expr_var_attr</span></p></td>
<td><p>`named_attr(${attname // name}, ${name})`</p></td>
</tr>
<tr class="ro4">
<td> </td>
<td><p>call</p></td>
<td><p>as_expr_call($name, @args)</p></td>
<td> </td>
<td> </td>
</tr>
<tr class="ro4">
<td> </td>
<td> </td>
<td> </td>
<td><p>entity</p></td>
<td><p>gen_entcall($name, @args)</p></td>
</tr>
<tr class="ro5">
<td> </td>
<td> </td>
<td> </td>
<td><p>var </p><p><span class="T2">→ as_expr_call_var</span></p></td>
<td><p>`${name} &amp;&amp; ${name}(${ gen_entlist(@args) })`</p></td>
</tr>
<tr class="ro5">
<td> </td>
<td> </td>
<td> </td>
<td><p>var attr</p><p><span class="T2">→ as_expr_call_var_attr</span></p></td>
<td><p>`named_attr(${attname // name}, ${ gen_entlist(@args) })`</p></td>
</tr>
<tr class="ro4">
<td><p>arg head</p></td>
<td><p>text</p></td>
<td><p>as_expr_text($val)</p></td>
<td> </td>
<td><p>qqvalue($val)</p></td>
</tr>
<tr class="ro4">
<td> </td>
<td><p>expr</p></td>
<td><p>as_expr_expr($val)</p></td>
<td> </td>
<td><p>$val</p></td>
</tr>
<tr class="ro4">
<td> </td>
<td><p>array</p></td>
<td><p>as_expr_array(@args)</p></td>
<td> </td>
<td><p>`[${ gen_entlist(@args) }]`</p></td>
</tr>
<tr class="ro4">
<td> </td>
<td><p>hash</p></td>
<td><p>as_expr_hash(@args)</p></td>
<td> </td>
<td><p>`{${ gen_entlist(@args) }}`</p></td>
</tr>
<tr class="ro4">
<td><p>rest</p></td>
<td><p>prop</p></td>
<td><p>as_expr_prop($name)</p></td>
<td> </td>
<td><p>$name</p></td>
</tr>
<tr class="ro4">
<td> </td>
<td><p>invoke</p></td>
<td><p>as_expr_invoke($name, @args)</p></td>
<td> </td>
<td><p>`${name}(${ gen_entlist(@args) })`</p></td>
</tr>
<tr class="ro4">
<td> </td>
<td><p>aref</p></td>
<td><p>as_expr_aref(@args)</p></td>
<td> </td>
<td><p>`[${ gen_entpath(@args) }]`</p></td>
</tr>
<tr class="ro4">
<td> </td>
<td><p>href</p></td>
<td><p>as_expr_href(@args)</p></td>
<td> </td>
<td><p>`{${ gen_entpath(@args) }}`</p></td>
</tr>
</table>

Note:

- `gen_entlist(@args)` is approximately:
  ```perl
  map {gen_entpath(@$_)} @args
  ```
- `gen_entcall($name, @args)` generates:
  ```js
  `$this->entity_${name}(${ gen_entlist(@args) })`
  ```

## TODO

- escape_now? escape_later? Which is true?
