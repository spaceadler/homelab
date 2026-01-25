#define DURATION 5              // 5 seconds
#define SAMPLE_RATE 44100       // we're going to sample 44100 times a second. the reason is related to the Nyquist frequency.
#define FREQ 440.0              // audio freuqency
#define NUM_SAMPLES (DURATION * SAMPLE_RATE)
#define VOLUME 1000

#include <stdint.h> // for specifiying the integer values; "uint16_t" for 2 bits, or "uint32_t" for 4 bits.
#include <string.h> // for writing strings directly into a char struct variable.
#include <stdio.h>  // for FILE, fwrite, etc.
#include <math.h>   // for sin()


#pragma pack(push, 1)             //stops padding, we need it to be flush.
typedef struct{
        char     ChunkID[4];      // = "RIFF";
        uint32_t ChunkSize;       // = 0;
        char     Format[4];       // = "WAVE";
        char     Subchunk1ID[4];  // = "fmt ";
        uint32_t Subchunk1Size;   // = 16;
        uint16_t AudioFormat;     // = 1;
        uint16_t NumChannels;     // = 2;
        uint32_t SampleRate;      // = 44100;
        uint32_t ByteRate;        // = ((SampleRate) * (NumChannels) * (BitsPerSample/8));
        uint16_t BlockAlign;      // - ((NumChannels) * (BitsPerSample/8);
        uint16_t BitsPerSample;   // = 16;
        char     Subchunk2ID[4];  // = "data";
        uint32_t Subchunk2Size;   // = ((NumSamples) * (NumChannels) * (BitsPerSample/8));
} WaveHeader;
#pragma pack(pop)                 // continue padding, it's just compiled c code after this so scheiÃŸegal.

int main(void)
{
        WaveHeader wave;

        memcpy(wave.ChunkID    , "RIFF", 4);   // grouping all the memcpy's together.
        memcpy(wave.Format     , "WAVE", 4);   // nothing really impressive going on here
        memcpy(wave.Subchunk1ID, "fmt ", 4);
        memcpy(wave.Subchunk2ID, "data", 4);

        wave.Subchunk1Size = 16;               //rest of the non-computable, non string informations.
        wave.AudioFormat   = 1;
        wave.NumChannels   = 2;
        wave.SampleRate    = SAMPLE_RATE;
        wave.BitsPerSample = 16;

        wave.Subchunk2Size = NUM_SAMPLES      * wave.NumChannels * (wave.BitsPerSample / 8);  // setting up definitions
        wave.ByteRate      = wave.SampleRate  * wave.NumChannels * (wave.BitsPerSample / 8);  // after just coding in the values
        wave.BlockAlign    = wave.NumChannels *(wave.BitsPerSample / 8);                      // like "RIFF", 0, whatnot.

        wave.ChunkSize = 36 + wave.Subchunk2Size;     // why exactly?

        FILE *pFile = fopen("test.wav", "wb");        // sets up file

        if (pFile == NULL)                            // contract driven design
        {
                return 1;
        }

        fwrite(&wave, sizeof(WaveHeader), 1, pFile);  // paste in the struct that we've made.

        int16_t sample;
        double t;
        double current_freq = 100.0;

        for(uint32_t i = 0; i < NUM_SAMPLES; i++)     // HUGE black box abstraction -- no idea what's going on here.
        {
                t = (double)i / SAMPLE_RATE;

                sample = (int16_t)(VOLUME * sin(2.0 * M_PI * current_freq * t));


                fwrite(&sample, sizeof(int16_t), 1, pFile);
                fwrite(&sample, sizeof(int16_t), 1, pFile);
                current_freq+= 0.05;
        }

        fclose(pFile);
}
