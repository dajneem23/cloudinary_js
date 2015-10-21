((root, factory) ->
  if (typeof define == 'function') && define.amd
    define ['utf8_encode', 'crc32', 'util', 'transformation', 'configuration', 'tags/imagetag', 'tags/videotag', 'require'], factory
  else if typeof exports == 'object'
    module.exports = factory(require('utf8_encode'), require('crc32'), require('util'), require('transformation'), require('configuration'), require('tags/imagetag'), require('tags/videotag'), require)
  else
    root.cloudinary ||= {}
    ###*
     * Resolves circular dependency
     * @private
    ###
    require = (name) ->
      switch name
        when 'tags/imagetag'
          root.cloudinary.ImageTag
        when 'tags/videotag'
          root.cloudinary.VideoTag

    root.cloudinary.Cloudinary = factory(root.cloudinary.utf8_encode, root.cloudinary.crc32, root.cloudinary.Util, root.cloudinary.Transformation, root.cloudinary.Configuration, root.cloudinary.ImageTag, root.cloudinary.VideoTag, require)

)(this,  (utf8_encode, crc32, Util, Transformation, Configuration, ImageTag, VideoTag, require )->
  ###*
   * Main Cloudinary class
  ###
  class Cloudinary
    CF_SHARED_CDN = "d3jpl91pxevbkh.cloudfront.net";
    OLD_AKAMAI_SHARED_CDN = "cloudinary-a.akamaihd.net";
    AKAMAI_SHARED_CDN = "res.cloudinary.com";
    SHARED_CDN = AKAMAI_SHARED_CDN;
    DEFAULT_POSTER_OPTIONS = { format: 'jpg', resource_type: 'video' };
    DEFAULT_VIDEO_SOURCE_TYPES = ['webm', 'mp4', 'ogv'];

    devicePixelRatioCache = {}
    responsiveConfig = {}
    responsiveResizeInitialized = false
    ###*
    * @const {object} Cloudinary.DEFAULT_IMAGE_PARAMS
    * Defaults values for image parameters.
    *
    * (Previously defined using option_consume() )
    ###
    @DEFAULT_IMAGE_PARAMS: {
      resource_type: "image"
      transformation: []
      type: 'upload'
    }

    ###*
    * Defaults values for video parameters.
    * @const {object} Cloudinary.DEFAULT_VIDEO_PARAMS
    * (Previously defined using option_consume() )
    ###
    @DEFAULT_VIDEO_PARAMS: {
      fallback_content: ''
      resource_type: "video"
      source_transformation: {}
      source_types: DEFAULT_VIDEO_SOURCE_TYPES
      transformation: []
      type: 'upload'
    }

    ###*
     * Main Cloudinary class
     * @class Cloudinary
     * @param {object} options - options to configure Cloudinary
     * @see Configuration for more details
     * @example
     *var cl = new cloudinary.Cloudinary( { cloud_name: "mycloud"});
     *var imgTag = cl.image("myPicID");
    ###
    constructor: (options)->
      configuration = new cloudinary.Configuration(options)

      # Provided for backward compatibility
      @config= (newConfig, newValue) ->
        configuration.config(newConfig, newValue)


      @fromDocument = ()->
        configuration.fromDocument()
        @


      @fromEnvironment = ()->
        configuration.fromEnvironment()
        @

      ###*
       * Initialize configuration.
       * @function Cloudinary#init
       * @see Configuration#init
       * @return {Cloudinary} this for chaining
      ###
      @init = ()->
        configuration.init()
        @

    @new = (options)-> new @(options)

    ###*
     * Return the resource type and action type based on the given configuration
     * @function Cloudinary#finalizeResourceType
     * @param {object|string} resourceType
     * @param {string} [type='upload']
     * @param {string} [urlSuffix]
     * @param {boolean} [useRootPath]
     * @param {boolean} [shorten]
     * @returns {string} resource_type/type
     * @ignore
    ###
    finalizeResourceType = (resourceType,type,urlSuffix,useRootPath,shorten) ->
      if Util.isPlainObject(resourceType)
        options = resourceType
        resourceType = options.resource_type
        type = options.type
        urlSuffix = options.url_suffix
        useRootPath = options.use_root_path
        shorten = options.shorten

      type?='upload'
      if urlSuffix?
        if resourceType=='image' && type=='upload'
          resourceType = "images"
          type = null
        else if resourceType== 'raw' && type== 'upload'
          resourceType = 'files'
          type = null
        else
          throw new Error("URL Suffix only supported for image/upload and raw/upload")
      if useRootPath
        if (resourceType== 'image' && type== 'upload' || resourceType == "images")
          resourceType = null
          type = null
        else
          throw new Error("Root path only supported for image/upload")
      if shorten && resourceType== 'image' && type== 'upload'
        resourceType = 'iu'
        type = null
      [resourceType,type].join("/")

    absolutize = (url) ->
      if !url.match(/^https?:\//)
        prefix = document.location.protocol + '//' + document.location.host
        if url[0] == '?'
          prefix += document.location.pathname
        else if url[0] != '/'
          prefix += document.location.pathname.replace(/\/[^\/]*$/, '/')
        url = prefix + url
      url

    ###*
     * Generate an resource URL.
     * @function Cloudinary#url
     * @param {string} publicId - the public ID of the resource
     * @param {Object} [options] - options for the tag and transformations, possible values include all {@link Transformation} parameters
     *                          and {@link Configuration} parameters
     * @param {string} [options.type='upload'] - the classification of the resource
     * @param {Object} [options.resource_type='image'] - the type of the resource
     * @return {HTMLImageElement} an image tag element
    ###
    url: (publicId, options = {}) ->
      options = Util.defaults({}, options, @config(), Cloudinary.DEFAULT_IMAGE_PARAMS)
      if options.type == 'fetch'
        options.fetch_format = options.fetch_format or options.format
        publicId = absolutize(publicId)

      transformation = new Transformation(options)
      transformationString = transformation.serialize()

      throw 'Unknown cloud_name' unless options.cloud_name

      throw 'URL Suffix only supported in private CDN' if options.url_suffix and !options.private_cdn

      # if publicId has a '/' and doesn't begin with v<number> and doesn't start with http[s]:/ and version is empty
      if publicId.search('/') >= 0 and !publicId.match(/^v[0-9]+/) and !publicId.match(/^https?:\//) and !options.version?.toString()
        options.version = 1

      if publicId.match(/^https?:/)
        if options.type == 'upload' or options.type == 'asset'
          url = publicId
        else
          publicId = encodeURIComponent(publicId).replace(/%3A/g, ':').replace(/%2F/g, '/')
      else
        # Make sure publicId is URI encoded.
        publicId = encodeURIComponent(decodeURIComponent(publicId)).replace(/%3A/g, ':').replace(/%2F/g, '/')
        if options.url_suffix
          if options.url_suffix.match(/[\.\/]/)
            throw 'url_suffix should not include . or /'
          publicId = publicId + '/' + options.url_suffix
        if options.format
          if !options.trust_public_id
            publicId = publicId.replace(/\.(jpg|png|gif|webp)$/, '')
          publicId = publicId + '.' + options.format

      prefix = cloudinaryUrlPrefix(publicId, options)
      resourceTypeAndType = finalizeResourceType(options.resource_type, options.type, options.url_suffix, options.use_root_path, options.shorten)
      version = if options.version then 'v' + options.version else ''

      url ||  Util.compact([
        prefix
        resourceTypeAndType
        transformationString
        version
        publicId
      ]).join('/').replace(/([^:])\/+/g, '$1/')



    video_url: (publicId, options) ->
      options = Util.assign({ resource_type: 'video' }, options)
      @url(publicId, options)

    video_thumbnail_url: (publicId, options) ->
      options = Util.assign({}, DEFAULT_POSTER_OPTIONS, options)
      @url(publicId, options)

    transformation_string: (options) ->
      new Transformation( options).serialize()

    ###*
     * Generate an image tag.
     * @function Cloudinary#image
     * @param {string} publicId - the public ID of the image
     * @param {Object} [options] - options for the tag and transformations
     * @return {HTMLImageElement} an image tag element
    ###
    image: (publicId, options={}) ->
      # generate a tag without the image src
      tag_options = Util.assign( {src: ''}, options)
      img = @imageTag(publicId, tag_options).toDOM()
      # cache the image src
      Util.setData(img, 'src-cache', @url(publicId, options))
      # set image src taking responsiveness in account
      @cloudinary_update(img, options)
      img

    ###*
     * Creates a new ImageTag instance, configured using this own's configuration.
     * @function Cloudinary#imageTag
     * @param {string} publicId - the public ID of the resource
     * @param {object} options - additional options to pass to the new ImageTag instance
     * @return {ImageTag} an instance of ImageTag
    ###
    imageTag: (publicId, options)->
      options = Util.defaults({}, options, @config())
      ImageTag ||= require('tags/imagetag')
      new ImageTag(publicId, options)

    video_thumbnail: (publicId, options) ->
      @image publicId, Util.merge( {}, DEFAULT_POSTER_OPTIONS, options)

    facebook_profile_image: (publicId, options) ->
      @image publicId, Util.assign({type: 'facebook'}, options)

    twitter_profile_image: (publicId, options) ->
      @image publicId, Util.assign({type: 'twitter'}, options)

    twitter_name_profile_image: (publicId, options) ->
      @image publicId, Util.assign({type: 'twitter_name'}, options)

    gravatar_image: (publicId, options) ->
      @image publicId, Util.assign({type: 'gravatar'}, options)

    fetch_image: (publicId, options) ->
      @image publicId, Util.assign({type: 'fetch'}, options)

    video: (publicId, options = {}) ->
      @videoTag(publicId, options).toHtml()

    videoTag: (publicId, options)->
      VideoTag ||= require('tags/videotag')
      options = Util.defaults({}, options, @config())
      new VideoTag(publicId, options)

    sprite_css: (publicId, options) ->
      options = Util.assign({ type: 'sprite' }, options)
      if !publicId.match(/.css$/)
        options.format = 'css'
      @url publicId, options

    responsive: (options) ->
      responsiveConfig = Util.merge(responsiveConfig or {}, options)
      @cloudinary_update 'img.cld-responsive, img.cld-hidpi', responsiveConfig
      responsiveResize = responsiveConfig['responsive_resize'] ? @config('responsive_resize') ? true
      if responsiveResize and !responsiveResizeInitialized
        responsiveConfig.resizing = responsiveResizeInitialized = true
        timeout = null
        window.addEventListener 'resize', =>
          debounce = responsiveConfig['responsive_debounce'] ? @config('responsive_debounce') ? 100

          reset = ->
            if timeout
              clearTimeout timeout
              timeout = null

          run = =>
            @cloudinary_update 'img.cld-responsive', responsiveConfig

          wait = ->
            reset()
            setTimeout (->
              reset()
              run()
            ), debounce

          if debounce
            wait()
          else
            run()

    calc_stoppoint: (element, width) ->
      stoppoints = Util.getData(element,'stoppoints') or @config('stoppoints') or defaultStoppoints
      if Util.isFunction stoppoints
        stoppoints(width)
      else
        if Util.isString stoppoints
          stoppoints = (parseInt(point) for point in stoppoints.split(',')).sort( (a,b) -> a - b )
        closestAbove stoppoints, width

    device_pixel_ratio: ->
      dpr = window?.devicePixelRatio or 1
      dprString = devicePixelRatioCache[dpr]
      if !dprString
        # Find closest supported DPR (to work correctly with device zoom)
        dprUsed = closestAbove(@supported_dpr_values, dpr)
        dprString = dprUsed.toString()
        if dprString.match(/^\d+$/)
          dprString += '.0'
        devicePixelRatioCache[dpr] = dprString
      dprString
    supported_dpr_values: [
      0.75
      1.0
      1.3
      1.5
      2.0
      3.0
    ]

    defaultStoppoints = (width) ->
      10 * Math.ceil(width / 10)

    closestAbove = (list, value) ->
      i = list.length - 2
      while i >= 0 and list[i] >= value
        i--
      list[i + 1]

    # Produce a number between 1 and 5 to be used for cdn sub domains designation
    cdnSubdomainNumber = (publicId)->
      crc32(publicId) % 5 + 1

    #  * cdn_subdomain - Boolean (default: false). Whether to automatically build URLs with multiple CDN sub-domains. See this blog post for more details.
    #  * private_cdn - Boolean (default: false). Should be set to true for Advanced plan's users that have a private CDN distribution.
    #  * secure_distribution - The domain name of the CDN distribution to use for building HTTPS URLs. Relevant only for Advanced plan's users that have a private CDN distribution.
    #  * cname - Custom domain name to use for building HTTP URLs. Relevant only for Advanced plan's users that have a private CDN distribution and a custom CNAME.
    #  * secure - Boolean (default: false). Force HTTPS URLs of images even if embedded in non-secure HTTP pages.
    cloudinaryUrlPrefix = (publicId, options) ->
      return '/res'+options.cloud_name if options.cloud_name?.indexOf("/")==0

      # defaults
      protocol = "http://"
      cdnPart = ""
      subdomain = "res"
      host = ".cloudinary.com"
      path = "/" + options.cloud_name

      # modifications
      if options.protocol
        protocol = options.protocol + '//'
      else if window?.location?.protocol == 'file:'
        protocol = 'file://'

      if options.private_cdn
        cdnPart = options.cloud_name + "-"
        path = ""

      if options.cdn_subdomain
        subdomain = "res-" + cdnSubdomainNumber(publicId)

      if options.secure
        protocol = "https://"
        subdomain = "res" if options.secure_cdn_subdomain == false
        if options.secure_distribution? &&
           options.secure_distribution != OLD_AKAMAI_SHARED_CDN &&
           options.secure_distribution != SHARED_CDN
          cdnPart = ""
          subdomain = ""
          host = options.secure_distribution

      else if options.cname
        protocol = "http://"
        cdnPart = ""
        subdomain = if options.cdn_subdomain then 'a'+((crc32(publicId)%5)+1)+'.' else ''
        host = options.cname
        #      path = ""

      [protocol, cdnPart, subdomain, host, path].join("")


    ###*
    * Finds all `img` tags under each node and sets it up to provide the image through Cloudinary
    * @function Cloudinary#processImageTags
    ###
    processImageTags: (nodes, options = {}) ->
      # similar to `$.fn.cloudinary`
      options = Util.defaults({}, options, @config())
      images = for node in nodes when node.tagName?.toUpperCase() == 'IMG'
          imgOptions = Util.assign({
            width: node.getAttribute('width')
            height: node.getAttribute('height')
            src: node.getAttribute('src')
          }, options)
          publicId = imgOptions['source'] || imgOptions['src']
          delete imgOptions['source']
          delete imgOptions['src']
          url = @url(publicId, imgOptions)
          imgOptions = new Transformation(imgOptions).toHtmlAttributes()
          Util.setData(node, 'src-cache', url)
          node.setAttribute('width', imgOptions.width)
          node.setAttribute('height', imgOptions.height)

      @cloudinary_update( images, options)
      this

    ###*
    * Update hidpi (dpr_auto) and responsive (w_auto) fields according to the current container size and the device pixel ratio.
    * Only images marked with the cld-responsive class have w_auto updated.
    * @function Cloudinary#cloudinary_update
    * @param {(Array|string|NodeList)} elements - the elements to modify
    * @param {object} options
    * @param {boolean|string} [options.responsive_use_stoppoints='resize']
    *  - when `true`, always use stoppoints for width
    * - when `"resize"` use exact width on first render and stoppoints on resize (default)
    * - when `false` always use exact width
    * @param {boolean} [options.responsive] - if `true`, enable responsive on this element. Can be done by adding cld-responsive.
    * @param {boolean} [options.responsive_preserve_height] - if set to true, original css height is preserved.
    *   Should only be used if the transformation supports different aspect ratios.
    ###
    cloudinary_update: (elements, options = {}) ->
      elements = switch
        when Util.isArray(elements)
          elements
        when elements.constructor.name == "NodeList"
          elements
        when Util.isString(elements)
          document.querySelectorAll(elements)
        else
          [elements]

      responsive_use_stoppoints = options['responsive_use_stoppoints'] ? @config('responsive_use_stoppoints') ? 'resize'
      exact = !responsive_use_stoppoints || responsive_use_stoppoints == 'resize' and !options.resizing
      for tag in elements when tag.tagName?.match(/img/i)
        if options.responsive
          Util.addClass(tag, "cld-responsive")
        attrs = {}
        src = Util.getData(tag, 'src-cache') or Util.getData(tag, 'src')
        if !src
          return
        responsive = Util.hasClass(tag, 'cld-responsive') and src.match(/\bw_auto\b/)
        if responsive
          container = tag.parentNode
          containerWidth = 0
          while container and containerWidth == 0
            containerWidth = Util.width(container)
            container = container.parentNode
          if containerWidth == 0
            # container doesn't know the size yet. Usually because the image is hidden or outside the DOM.
            return
          requestedWidth = if exact then containerWidth else @calc_stoppoint(tag, containerWidth)
          currentWidth = Util.getData(tag, 'width') or 0
          if requestedWidth > currentWidth
            # requested width is larger, fetch new image
            Util.setData(tag, 'width', requestedWidth)
          else
            # requested width is not larger - keep previous
            requestedWidth = currentWidth
          src = src.replace(/\bw_auto\b/g, 'w_' + requestedWidth)
          attrs.width = null
          if !options.responsive_preserve_height
            attrs.height = null
        # Update dpr according to the device's devicePixelRatio
        attrs.src = src.replace(/\bdpr_(1\.0|auto)\b/g, 'dpr_' + @device_pixel_ratio())
        Util.setAttributes(tag, attrs)
      this

    ###*
    * Provide a transformation object, initialized with own's options, for chaining purposes.
    * @function Cloudinary#transformation
    * @param {object} options
    * @return {Transformation}
    ###
    transformation: (options)->
      Transformation.new( @config()).fromOptions(options).setParent( this)
  Cloudinary
)

#/**
# * @license
# * lodash 3.10.0 (Custom Build) <https://lodash.com/>
#* Build: `lodash modern -o ./lodash.js`
#* Copyright 2012-2015 The Dojo Foundation <http://dojofoundation.org/>
#* Based on Underscore.js 1.8.3 <http://underscorejs.org/LICENSE>
#* Copyright 2009-2015 Jeremy Ashkenas, DocumentCloud and Investigative Reporters & Editors
#* Available under MIT license <https://lodash.com/license>
#*/