use Test::Nginx::Socket 'no_plan';
use Cwd qw(cwd);

my $pwd = cwd();

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';
$ENV{TEST_COVERAGE} ||= 0;

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;/usr/local/share/lua/5.1/?.lua;;";
    error_log logs/error.log debug;

    init_by_lua_block {
        if $ENV{TEST_COVERAGE} == 1 then
            jit.off()
            require("luacov.runner").init()
        end
    }
};

no_long_string();
#no_diff();

run_tests();

__DATA__
=== TEST 1 Test that pipelined requests can be read correctly.
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local http = require "resty.http"
            local httpc = http.new()
            httpc:connect({
                scheme = "http",
                host = "127.0.0.1",
                port = ngx.var.server_port
            })

            local responses = httpc:request_pipeline{
                {
                    path = "/b",
                },
                {
                    path = "/c",
                },
                {
                    path = "/d",
                }
            }

            for i,r in ipairs(responses) do
                if r.status then
                    ngx.say(r.status)
                    ngx.say(r.headers["X-Res"])
                    ngx.say(r:read_body())
                end
            end
        ';
    }
    location = /b {
        content_by_lua '
            ngx.status = 200
            ngx.header["X-Res"] = "B"
            ngx.print("B")
        ';
    }
    location = /c {
        content_by_lua '
            ngx.status = 404
            ngx.header["X-Res"] = "C"
            ngx.print("C")
        ';
    }
    location = /d {
        content_by_lua '
            ngx.status = 200
            ngx.header["X-Res"] = "D"
            ngx.print("D")
        ';
    }
--- request
GET /a
--- response_body
200
B
B
404
C
C
200
D
D
--- no_error_log
[error]
[warn]


=== TEST 2: Test we can handle timeouts on reading the pipelined requests.
--- http_config eval: $::HttpConfig
--- config
    location = /a {
        content_by_lua '
            local http = require "resty.http"
            local httpc = http.new()
            httpc:connect({
                scheme = "http",
                host = "127.0.0.1",
                port = ngx.var.server_port
            })
            httpc:set_timeout(1)

            local responses = httpc:request_pipeline{
                {
                    path = "/b",
                },
                {
                    path = "/c",
                },
            }

            for i,r in ipairs(responses) do
                if r.status then
                    ngx.say(r.status)
                    ngx.say(r.headers["X-Res"])
                    ngx.say(r:read_body())
                end
            end
        ';
    }
    location = /b {
        content_by_lua '
            ngx.status = 200
            ngx.header["X-Res"] = "B"
            ngx.print("B")
        ';
    }
    location = /c {
        content_by_lua '
            ngx.status = 404
            ngx.header["X-Res"] = "C"
            ngx.sleep(1)
            ngx.print("C")
        ';
    }
--- request
GET /a
--- response_body
200
B
B
--- no_error_log
[warn]
--- error_log eval
[qr/timeout/]
