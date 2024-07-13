package com.example.liveness;

import android.graphics.ImageFormat;
import android.graphics.Rect;
import android.graphics.YuvImage;

import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.util.List;

public class YuvConverter {
    /**
     * Converts an NV21 image into JPEG compressed.
     * @param nv21 byte[] of the input image in NV21 format
     * @param width Width of the image.
     * @param height Height of the image.
     * @param quality Quality of compressed image(0-100)
     * @return byte[] of a compressed Jpeg image.
     */
    public static byte[] NV21toJPEG(byte[] nv21, int width, int height, int quality) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        YuvImage yuv = new YuvImage(nv21, ImageFormat.NV21, width, height, null);
        yuv.compressToJpeg(new Rect(0, 0, width, height), quality, out);
        return out.toByteArray();
    }

    /**
     * Format YUV_420 planes in to NV21.
     * Removes strides from planes and combines the result to single NV21 byte array.
     * @param planes  List of Bytes list
     * @param strides contains the strides of each plane. The structure :
     *                strideRowFirstPlane,stridePixelFirstPlane, strideRowSecondPlane
     * @param width   Width of the image
     * @param height  Height of given image
     * @return NV21 image byte[].
     */
       public static byte[] YUVtoNV21(List<byte[]> planes, int[] strides, int width, int height) {
        byte[] nv21 = new byte[width * height * 3 / 2];
        int ySize = width * height;
        int uvSize = width * height / 4;

        // Copy Y plane
        if (planes.get(0).length >= ySize) {
            System.arraycopy(planes.get(0), 0, nv21, 0, ySize);
        } else {
            // Handle the case where the Y plane is split into rows
            int yStride = strides[0];
            for (int row = 0; row < height; row++) {
                System.arraycopy(planes.get(0), row * yStride, nv21, row * width, width);
            }
        }

        // Interleave U and V planes
        byte[] uBuffer = planes.get(1);
        byte[] vBuffer = planes.get(2);
        int uvStride = strides[1];
        int uvHeight = height / 2;
        int uvWidth = width / 2;

        for (int row = 0; row < uvHeight; row++) {
            for (int col = 0; col < uvWidth; col++) {
                int bufferIndex = row * uvStride + col;
                int nv21Index = ySize + row * width + col * 2;

                nv21[nv21Index] = vBuffer[bufferIndex];
                nv21[nv21Index + 1] = uBuffer[bufferIndex];
            }
        }

        return nv21;
    }
}
