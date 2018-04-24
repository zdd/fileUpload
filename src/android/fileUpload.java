package cordova.plugin.file.upload;

import android.util.Log;

import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CallbackContext;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.DataOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.Random;

/**
 * 文件分块上传  4M/次
 */
public class fileUpload extends CordovaPlugin {

    private static final int CHUNK_SIZE = 1024 * 1024 * 4;
    // test
    //private static final int CHUNK_SIZE = 3;
    private String uploadUrl = "";
    private String fileName = "";
    private int i = 1;
    private int j = 0;
    private int start = 0;
    private byte[] bytesStream = null;
    private int loopTimes = 0;
    private static final int MAX_BUFFER_SIZE = 16 * 1024;

    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
        if (action.equals("upload")) {
            String filePath = args.getString(0);
            uploadUrl = args.getString(1);
            String fileKey = args.getString(2);
            fileName = args.getString(3);
            String mimeType = args.getString(4);
            String headInfo = args.getString(6);
            i = 1;
            start = 0;
            bytesStream = null;
            loopTimes = 0;
            try {
                bytesStream = readFile(filePath);
                Log.i("----", bytesStream.length + "");
            } catch (IOException e) {
                e.printStackTrace();
            }
            // test
//      bytesStream = new byte[]{'a','1','2','3','4','5','6','7','8','b'};

            if (null != bytesStream) {
                loopTimes = bytesStream.length % CHUNK_SIZE == 0 ? bytesStream.length / CHUNK_SIZE : bytesStream.length / CHUNK_SIZE + 1;
                this.coolMethod(getChunkData(), callbackContext);
            }
            return true;
        }
        return false;
    }

    private byte[] readFile(String fileName) throws IOException {
//    String res = "";
        File file = new File(fileName);
        FileInputStream fis = new FileInputStream(file);
        int length = fis.available();
        byte[] buffer = new byte[length];
        fis.read(buffer);
//    res = new String(buffer, "UTF-8");
        fis.close();
        return buffer;
    }

    private String getChunkData() {
        int length = 0;
        int surplus_length = 0;
        if (null != bytesStream && loopTimes >= i) {
            if (bytesStream.length > CHUNK_SIZE) {
                byte[] chunkData = new byte[bytesStream.length - start > CHUNK_SIZE ? CHUNK_SIZE : bytesStream.length - start];
                surplus_length = bytesStream.length - start;
                if (surplus_length >= CHUNK_SIZE) {
                    length = CHUNK_SIZE;
                } else {
                    length = surplus_length;
                }
                System.arraycopy(bytesStream, start, chunkData, 0, length);
                return chunkUpload(chunkData, start + length);
            } else {
                return chunkUpload(bytesStream, bytesStream.length);
            }
        }
        return null;
    }

    private String chunkUpload(byte[] chunk, int chunkEnd) {
        String result = "";
        HttpURLConnection httpConn = null;
        try {
            String BOUNDARY = "---------CCHTTPAPIFormBoundaryEEXX" + new Random().nextInt(65536); // 定义数据分隔线
            String pathUrl = uploadUrl;
            URL url = new URL(pathUrl);
            httpConn = (HttpURLConnection) url.openConnection();

            ////设置连接属性
            httpConn.setDoOutput(true);//使用 URL 连接进行输出
            httpConn.setDoInput(true);//使用 URL 连接进行输入
            httpConn.setUseCaches(false);//忽略缓存
            httpConn.setRequestMethod("POST");//设置URL请求方法
            //设置请求属性
            //获得数据字节数据，请求数据流的编码，必须和下面服务器端处理请求流的编码一致
//      byte[] requestStringBytes = requestString.getBytes(ENCODING_UTF_8);
//      httpConn.setRequestProperty("Content-length", "" + chunk.length);
//      httpConn.setRequestProperty("Content-Type", "application/octet-stream");
//      httpConn.setRequestProperty("Connection", "Keep-Alive");// 维持长连接
//      httpConn.setRequestProperty("Charset", "UTF-8");
            httpConn.setRequestProperty("Accept", "text/*");
            httpConn.setRequestProperty("Content-Type", "multipart/form-data");
            httpConn.setRequestProperty("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_4)");
//      httpConn.setRequestProperty("Content-Length", "" + chunk.length);
            httpConn.setRequestProperty("Connection", "Keep-Alive");
            httpConn.setRequestProperty("Cache-Control", "no-cache");
//      httpConn.setRequestProperty("Content-Range", "bytes 0-100/500");
            httpConn.setRequestProperty("Charset", "UTF-8"); //Content-Range: bytes x-y/z
//      httpConn.setRequestProperty("Content-Type", "application/octet-stream");
            httpConn.setRequestProperty("Content-Type", "multipart/form-data; boundary=" + BOUNDARY);
            httpConn.setRequestProperty("Content-Range", "bytes " + start + "-" + (chunkEnd - 1) + "/" + chunk.length);
            //
//      String name = URLEncoder.encode("Mr.Wang", "utf-8");
//      httpConn.setRequestProperty("NAME", name);

            OutputStream out = new DataOutputStream(httpConn.getOutputStream());
            StringBuilder sb = new StringBuilder();
            sb.append("--").append(BOUNDARY).append("\r\n");
            sb.append("Content-Disposition: form-data;name=\"file" + fileName + "\";filename=\"" + fileName + "\"\r\n");
            sb.append("Content-Type: application/octet-stream\r\n");
            sb.append("\r\n");
            byte[] data = sb.toString().getBytes();
            out.write(data);
            out.write(chunk);
            out.write("\r\n".getBytes());
            // 定义最后数据分隔线
            byte[] end_data = ("--" + BOUNDARY + "--\r\n").getBytes();
            out.write(end_data);
            out.flush();
            out.close();

            // 定义BufferedReader输入流来读取URL的响应
            BufferedReader reader = new BufferedReader(new InputStreamReader(httpConn.getInputStream()));
            StringBuffer resultBuf = new StringBuffer("");
            String line = null;
            while ((line = reader.readLine()) != null) {
                resultBuf.append(line);
            }
            reader.close();
            httpConn.disconnect();
            Log.i("视频总大小", +bytesStream.length + "");
            Log.i("第 " + i + " 次上传大小" + chunk.length, "cc返回值" + resultBuf.toString());
            JSONObject resultJson = new JSONObject(resultBuf.toString());
            if (resultJson.getString("result").equals("0")) {
                start = i * CHUNK_SIZE;
                i++;
                if (!resultJson.getString("received").equals("0") && !resultJson.getString("received").equals("-1")) {
                    getChunkData();
                }
            } else {
                if (j < 3) {
                    j++;
                    chunkUpload(chunk, chunkEnd);
                }
            }
            result = resultJson.getString("msg");
        } catch (IOException e) {
            e.printStackTrace();
        } catch (JSONException e) {
            e.printStackTrace();
        } finally {
            if (httpConn != null)
                httpConn.disconnect();
        }
        return result;
    }

    private void coolMethod(String message, CallbackContext callbackContext) {
        if (message != null && message.length() > 0) {
            callbackContext.success(message);
        } else {
            callbackContext.error("Expected one non-empty string argument.");
        }
    }
}
