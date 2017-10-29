#= require ./record

u = up.util

class up.Request extends up.Record

  fields: ->
    ['method', 'url', 'data', 'target', 'failTarget', 'headers', 'timeout']

  constructor: (options) ->
    super(options)
    @method = u.normalizeMethod(options.method)
    @headers ||= {}
    @extractHashFromUrl()
    if @data && !u.methodAllowsPayload(@method) && !u.isFormData(@data)
      @transferDataToUrl()

  extractHashFromUrl: =>
    urlParts = u.parseUrl(@url)
    # Remember the #hash for later revealing.
    # It will be lost during normalization.
    @hash = urlParts.hash
    @url = u.normalizeUrl(urlParts, hash: false)

  transferDataToUrl: =>
    # GET methods are not allowed to have a payload, so we transfer { data } params to the URL.
    query = u.requestDataAsQuery(@data)
    separator = if u.contains(@url, '?') then '&' else '?'
    @url += separator + query
    # Now that we have transfered the params into the URL, we delete them from the { data } option.
    @data = undefined

  isIdempotent: =>
    up.proxy.isIdempotentMethod(@method)

  send: =>
    # We will modify this request below.
    # This would confuse API clients and cache key logic in up.proxy.
    new Promise (resolve, reject) =>
      xhr = new XMLHttpRequest()
      xhr.open(@method, @url)

      xhrHeaders = u.copy(@headers)

      xhrData = @data
      if u.isPresent(xhrData)
        if u.isFormData(xhrData)
          delete xhrHeaders['Content-Type'] # let the browser set the content type
        else
          xhrData = u.requestDataAsQuery(xhrData, purpose: 'form')
          xhrHeaders['Content-Type'] = 'application/x-www-form-urlencoded'
      else
        # XMLHttpRequest expects null for an empty body
        xhrData = null

      xhrHeaders[up.protocol.config.targetHeader] = @target if @target
      xhrHeaders[up.protocol.config.failTargetHeader] = @failTarget if @failTarget

      for header, value of xhrHeaders
        xhr.setRequestHeader(header, value)

      resolveWithResponse = =>
        response = @buildResponse(xhr)
        console.info("!!! response is %o, status is %o, success is %o", response, response.status, response.isSuccess())
        console.info("!!! resolving with %o", response)
        if response.isSuccess()
          resolve(response)
        else
          reject(response)

      xhr.onload = resolveWithResponse
      xhr.onerror = resolveWithResponse
      xhr.ontimeout = resolveWithResponse

      xhr.timeout = @timeout if @timeout

      xhr.send(xhrData)

  buildResponse: (xhr) =>
    responseAttrs =
      method: @method
      url: @url
      body: xhr.responseText
      status: xhr.status
      request: @
      xhr: xhr

    if urlFromServer = up.protocol.locationFromXhr(xhr)
      responseAttrs.url = urlFromServer
      # If the server changes a URL, it is expected to signal a new method as well.
      responseAttrs.method = up.protocol.methodFromXhr(xhr) ? 'GET'

    new up.Response(responseAttrs)

  isCachable: =>
    @isIdempotent() && !u.isFormData(@data)

  cacheKey: =>
    [@url, @method, u.requestDataAsQuery(@data), @target].join('|')

  @normalize: (object) ->
    if object instanceof @
      # This object has gone through instantiation and normalization before.
      object
    else
      new @(object)
