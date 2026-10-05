# Task F: HTTP caching: Cache-Control, ETag, conditional request, 304

**What it shows** (all through the edge, `https://app.subspace-67.test/api/cache-demo`)
| File | Proof |
|---|---|
| 01_head_cache_headers.txt | `curl -I` (HEAD): `cache-control: public, max-age=60`, `etag: "6adb0ec0cb57508d"`, `last-modified: Tue, 29 Sep 2026 00:00:00 GMT`, `content-length: 225` |
| 02_conditional_get_304.txt | `If-None-Match: "6adb0ec0cb57508d"` -> **`HTTP/2 304`**, validators repeated, **no body** |
| 03_normal_get_200.txt | normal GET -> **`HTTP/2 200`** with the full 225-byte body |
| 04_304_from_both_backends.txt | 4 conditional requests -> 304 from **A, B, A, B**: the body is byte-identical on both backends, so both compute the **same ETag** and either one can confirm "not modified" |
| 05_wrong_etag_full_200.txt | a non-matching ETag -> full 200 (the validator really is compared) |
| 06_if_modified_since_304.txt | date-based validator `If-Modified-Since` (= Last-Modified) -> 304 as well |
| 07_curl_etag_save_compare.txt | curl acting as a tiny cache: `--etag-save` (200, **225** body bytes) then `--etag-compare` (**304, 0** body bytes) |
| 08_status_is_no_store.txt | `/api/status` has `cache-control: no-store`: never cached, so load-balancing tests always reach a backend |

**Three different situations** (the key viva point)
1. **Fresh cache hit**: while the stored copy is younger than `max-age=60`, the browser reuses it **without sending
   any request**. Nothing crosses the network; the server never knows.
2. **Conditional request (revalidation)**: when the copy is stale (or on a normal reload) the browser asks
   "has it changed?" with `If-None-Match: <ETag>` (or `If-Modified-Since`). If not, the server replies **304 Not Modified**
   with headers only (a few hundred bytes instead of the body), and the browser reuses its copy and treats it as fresh
   for another 60 s.
3. **Full new request**: no stored copy, a hard reload, or the ETag no longer matches -> **200** with the full body.

**Showing it in browser DevTools on demo day** (Chrome/Safari, DevTools -> Network, "Disable cache" **unchecked**):
- open `https://app.subspace-67.test/api/cache-demo` -> Status 200, Size 225 B (full request, case 3);
- within 60 s click into the address bar and press Enter (or open it in a new tab) -> Status `200` with Size
  **"(disk cache)"/"(memory cache)"**, and no request reaches nginx (case 1, fresh hit; nginx's access log shows nothing);
- after 60 s, or press Cmd-R (normal reload) -> request headers show `If-None-Match`, Status **304**, tiny transfer (case 2);
- Shift-Cmd-R (hard reload) -> no validators sent, full 200 again (case 3).

**Which layer**: application layer (HTTP/1.1 and HTTP/2 caching semantics, RFC 9111 / RFC 9110 conditional requests).

**Why**: caching saves bandwidth and latency. `max-age` avoids requests entirely; ETag/304 avoids resending bodies
that haven't changed. Identical bodies (and therefore identical ETags) on both backends matter behind a load balancer,
otherwise a revalidation that lands on the "other" backend would wrongly return the whole body again.
