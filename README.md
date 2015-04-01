<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [Hookscript tests](#hookscript-tests)
- [Running tests](#running-tests)
- [YAML format](#yaml-format)
  - [`request`](#request)
  - [`response`](#response)
    - [`content`](#content)
    - [`headers`](#headers)
    - [`status_code`](#status_code)
  - [`post_params`](#post_params)
  - [`creation`](#creation)
    - [`status`](#status)
    - [`error_message`](#error_message)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# Hookscript tests

This repository includes some automated tests for Hookscript language implementations. Each language implementation must be able to pass each of these tests.  The implementations are also used to generate automated documentation.

# Running tests

...

# YAML format

Each test is described by a [YAML](http://yaml.org/) file (for example, `hello.yaml`).  The file's base name (`hello`) provides the test's name.  When a language implements this test, the implementation file must have the same base name (for example, Go would have `hello.go`).

The first line of each test is a comment that summarizes what the test is about.  The rest of the file is a YAML array describing HTTP requests and their expected responses.  For example, this snippet:

```yaml
-
    request: GET /
    response: "Hello, world!\n"
```

describes a `GET` request whose response should be the text `Hello, world!` followed by a newline character.

Before a test begins, a language's implementation file is used to create a new script.  The HTTP requests described in the YAML file are executed, in order, against this script.  The actual results are compared against the expectations.

## `request`

A test's request is described under a `request` key.  The simplest possible request gives an HTTP method and its relative path, as a combined string.  This is just like the equivalent line in a raw HTTP request.  The path may include URL parameters.  For example,

```yaml
request: GET /?whom=Joe
```

## `response`

A test's expected response is described under a `response` key.  The simplest possible response gives the expected body content.  For example,

```yaml
response: "Hello, world!\n"
```

demands that the content be equal to the given string.  This style implies a `Content-Type: text/plain` header.  It also implies that the HTTP response's status code is `200`.

### `content`

Describes the expected content from a response.  The following two descriptions are identical:

```yaml
response: "Howdy"
```

and

```yaml
response:
    content: "Howdy"
```

However, the value of a `content` key may start and end with a `/` character to indicate regular expression matching.  For example,

```yaml
response:
    content: /^Script exited with code [1-9][0-9]*/
```

### `headers`

Indicates headers which must be included in the HTTP response.  The HTTP response may include other headers, but the ones describe must be present.  Header names are described in lower case with dash characters replaced by underscores.

For example, to stipulate that a response have a `Content-Type` header whose value is `text/html` one can use:

```yaml
headers:
    content_type: text/html
```

### `status_code`

This integer value provides the response's expected HTTP status code.  If omitted, the default is `200`.

## `post_params`

For a POST request, a `post_params` key describes parameters which should be sent as the request body.  Keys and values are encoded as `application/x-www-form-urlencoded`.

## `creation`

This key is slightly different than the others.  Instead of describing a request/response pair, it's used to describe what happens when a script is created.  An array element with the `creation` key, if it exists, must be the first element in a test file.

This key is often used to test for compilation errors for a language.

### `status`

The expected HTTP status code from Hookscript's API after attempting to create the new script.

### `error_message`

The content (or slash-delimited regular expression) describing Hookscript's API error message after attempting to create the script.
