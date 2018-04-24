var exec = require('cordova/exec');
// var ProgressEvent = require('cordova-plugin-fileUpload.ProgressEvent');

// exports.coolMethod = function(filePath, server, options, success, error) {
//     exec(success, error, 
//         "fileUpload", "upload", [filePath, server, options]);
// };

// function newProgressEvent(result) {
//     var pe = new ProgressEvent();
//     pe.lengthComputable = result.lengthComputable;
//     pe.loaded = result.loaded;
//     pe.total = result.total;
//     return pe;
// }

// var FileError = function(code, source, target, status, body, exception) {
//     this.code = code || null;
//     this.source = source || null;
//     this.target = target || null;
//     this.http_status = status || null;
//     this.body = body || null;
//     this.exception = exception || null;
// };

exports.upload = function(filePath, server, successCallback, progressCallback, errorCallback, options) {
    
    var fileKey = null;
    var fileName = null;
    var mimeType = null;
    var headers = null;
    var params = null;

    if (options) {
        fileKey = options.fileKey;
        fileName = options.fileName;
        mimeType = options.mimeType;
        headers = options.headers;
        if (options.params) {
            params = options.params;
        } else {
            params = {};
        }
    }
    
    // var fail = errorCallback && function(e) {
    //     var error = new FileError(e.code, e.source, e.target, e.http_status, e.body, e.exception);
    //     errorCallback(error);
    // };
    // var self = this;
    var win = function(result) {
        if (typeof result.lengthComputable != "undefined") {
            progressCallback(result);
        } else {
            if (successCallback) {
                successCallback(result);
            }
        }
    };
    exec(win, errorCallback, 'fileUpload', 'upload', [filePath, server, fileKey, fileName, mimeType, params, headers]);    
}
