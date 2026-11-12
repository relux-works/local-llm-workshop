#!/usr/bin/env python3
"""Workshop helper for prewarmed llama-server sessions. Python stdlib only.

capture  Fake OpenAI endpoint: saves every chat request body Pi sends and answers "ok" without touching a model.
warm     Takes a captured request, renders it with the server's own template (/apply-template), cuts it right
         before the last user turn, fills that prefix into a slot (/completion, n_predict 0) and saves the slot.
         The saved slot then ends exactly where Pi's next request begins, so a restore plus Pi's next question
         reads only the question.
restore  Restores a saved slot file into a slot.
ask      Restores, sends the captured request with a new question, prints prompt_n (the acceptance check).
"""
import argparse, copy, glob, http.server, json, os, sys, time, urllib.request

SENTINEL = "@@WS_SENTINEL_7f3a@@"


def post(url, body, timeout=7200):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def latest(path):
    if os.path.isdir(path):
        files = sorted(glob.glob(os.path.join(path, "req-*.json")))
        if not files:
            sys.exit(f"no captured requests in {path}")
        path = files[-1]
    print(f"request: {path}")
    return json.load(open(path))


def set_last_user(body, text):
    msgs = body["messages"]
    for m in reversed(msgs):
        if m.get("role") == "user":
            if isinstance(m.get("content"), list):
                m["content"] = [{"type": "text", "text": text}]
            else:
                m["content"] = text
            return body
    sys.exit("no user message in the captured request")


def prefix_for(server, body):
    b = set_last_user(copy.deepcopy(body), SENTINEL)
    b.pop("stream", None)
    b.pop("stream_options", None)
    prompt = post(server + "/apply-template", b)["prompt"]
    s = prompt.find(SENTINEL)
    if s < 0:
        sys.exit("sentinel not found in the rendered prompt")
    cut = prompt.rfind("<|im_start|>user", 0, s)
    if cut < 0:
        sys.exit("no '<|im_start|>user' before the sentinel: not a ChatML template")
    return prompt[:cut]


def cmd_capture(a):
    os.makedirs(a.out, exist_ok=True)

    class H(http.server.BaseHTTPRequestHandler):
        def log_message(self, *x):
            pass

        def _send(self, code, ctype, data):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            self._send(200, "application/json", json.dumps({"object": "list", "data": [{"id": "capture", "object": "model"}]}).encode())

        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
            name = os.path.join(a.out, time.strftime("req-%Y%m%dT%H%M%S") + f"-{int(time.time()*1000)%1000:03d}.json")
            json.dump(body, open(name, "w"), ensure_ascii=False)
            print(f"captured {name}: {len(body.get('messages', []))} messages", flush=True)
            base = {"id": "cap", "created": 0, "model": body.get("model", "capture")}
            if body.get("stream"):
                c1 = dict(base, object="chat.completion.chunk", choices=[{"index": 0, "delta": {"role": "assistant", "content": "ok"}, "finish_reason": None}])
                c2 = dict(base, object="chat.completion.chunk", choices=[{"index": 0, "delta": {}, "finish_reason": "stop"}],
                          usage={"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2})
                data = f"data: {json.dumps(c1)}\n\ndata: {json.dumps(c2)}\n\ndata: [DONE]\n\n".encode()
                self._send(200, "text/event-stream", data)
            else:
                r = dict(base, object="chat.completion", choices=[{"index": 0, "message": {"role": "assistant", "content": "ok"}, "finish_reason": "stop"}],
                         usage={"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2})
                self._send(200, "application/json", json.dumps(r).encode())

    print(f"capture proxy on 127.0.0.1:{a.listen}, saving to {a.out}", flush=True)
    http.server.ThreadingHTTPServer(("127.0.0.1", a.listen), H).serve_forever()


def cmd_warm(a):
    body = latest(a.req)
    prefix = prefix_for(a.server, body)
    n = len(post(a.server + "/tokenize", {"content": prefix, "add_special": True, "parse_special": True})["tokens"])
    print(f"prefix: {len(prefix)} chars, {n} tokens; filling slot {a.slot} ...", flush=True)
    t = time.time()
    r = post(a.server + "/completion", {"prompt": prefix, "n_predict": 0, "cache_prompt": True, "id_slot": a.slot})
    tm = r.get("timings", {})
    print(f"filled in {time.time()-t:.1f} s: prompt_n {tm.get('prompt_n')}, cache_n {tm.get('cache_n')}, "
          f"{tm.get('prompt_per_second', 0):.1f} tok/s", flush=True)
    t = time.time()
    s = post(a.server + f"/slots/{a.slot}?action=save", {"filename": a.slot_file})
    print(f"saved {a.slot_file}: n_saved {s.get('n_saved')}, {s.get('n_written', 0)/1e9:.2f} GB, {time.time()-t:.1f} s")


def cmd_restore(a):
    t = time.time()
    r = post(a.server + f"/slots/{a.slot}?action=restore", {"filename": a.slot_file})
    print(f"restored {a.slot_file}: n_restored {r.get('n_restored')}, {r.get('n_read', 0)/1e9:.2f} GB, {time.time()-t:.1f} s")


def cmd_ask(a):
    cmd_restore(a)
    body = set_last_user(latest(a.req), a.question)
    body["stream"] = False
    body.pop("stream_options", None)
    body["max_tokens"] = a.max_tokens
    t = time.time()
    r = post(a.server + "/v1/chat/completions", body)
    tm = r.get("timings", {})
    print(f"answer in {time.time()-t:.1f} s: prompt_n {tm.get('prompt_n')} (must be about the question length), "
          f"cache_n {tm.get('cache_n')}, prefill {tm.get('prompt_per_second', 0):.1f} tok/s, "
          f"decode {tm.get('predicted_per_second', 0):.1f} tok/s")
    msg = r["choices"][0]["message"]
    print((msg.get("content") or msg.get("reasoning_content") or "")[:400])


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = p.add_subparsers(dest="cmd", required=True)
    c = sp.add_parser("capture"); c.add_argument("--listen", type=int, default=18091); c.add_argument("--out", default="cap")
    for name in ("warm", "restore", "ask"):
        x = sp.add_parser(name)
        x.add_argument("--server", default="http://127.0.0.1:8080")
        x.add_argument("--slot", type=int, default=0)
        x.add_argument("--slot-file", required=True)
        if name in ("warm", "ask"):
            x.add_argument("--req", default="cap", help="captured request file, or a directory (latest file)")
        if name == "ask":
            x.add_argument("--question", default="Ответь одним предложением: о чём этот код?")
            x.add_argument("--max-tokens", type=int, default=64)
    a = p.parse_args()
    {"capture": cmd_capture, "warm": cmd_warm, "restore": cmd_restore, "ask": cmd_ask}[a.cmd](a)


if __name__ == "__main__":
    main()
