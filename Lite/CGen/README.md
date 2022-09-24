# Brief Internals of YATT::Lite::CGen::Perl

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
<!yatt:widget foo x=text y=html z=value w=list>

<!yatt:widget bar x=text y=html z=value w=list>

```

### In YATT::Lite::CGen::Perl:

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
