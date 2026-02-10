# Embedded WAV

I wanted to understand how binary files actually work. Usually, we just import a library and hit play(). But I wanted to know what bytes actually go onto the disk to make a speaker move.  
This project, wav.c, does four things in one go:

1. **Builds a Header:** Manually constructs the 44-byte ID card that tells the computer "Hey, I'm a WAV file."  
2. **Does Physics:** Simulates a 440Hz sine wave using math.  
3. **Quantizes:** Turns that smooth math wave into jagged digital steps (16-bit integers).  
4. **Streams:** Writes it straight to the disk.

## **1. The math (it's actually simple)**

To make a sound, you need a sine wave. The formula is $$y = \sin(2\pi f t)$$.
But computers don't know what "time" ($t$) is; they only know "samples" (indexes in an array). So we have to convert our loop counter $i$ into time using the sample rate (44,100 Hz):

$$t = \frac{i}{44100}$$
So the code is basically just:

```c
double t = (double)i / SAMPLE_RATE;  
sample = sin(2.0 * PI * 440.0 * t);
```

That's it. That's the whole engine.

## **2. The header & why structs are the best**

A WAV file needs a specific 44-byte header at the start. If you mess up a single byte, the file is corrupted.  
I could have written the bytes one by one, but that's messy. Instead, I used a C **struct**. So I define the shape of the data I want, fill it with values, and then stamp the whole thing onto the disk in one go.

### **The "Packing" Trick**

There is a catch. C compilers like to add empty "padding" bytes between variables to make memory access faster. If I let the compiler do that, my 44-byte header becomes 48 bytes, and the file breaks.
I had to use a special command: \#pragma pack(1). This tells the compiler: "Do not add padding. Squeeze these bytes together tightly." This ensures the binary output matches the Microsoft WAV specification perfectly.

## **3. My hilarious screw-ups**

It wasn't smooth sailing. Here is how I almost broke my ears.

### **The "Supersonic" Incident**

I tried to make a "chirp" sound (frequency goes up over time).  
**The Mistake:** I added \+1 to the frequency *every single sample*.  
**The Result:** Since there are 44,100 samples per second, the frequency shot up to 44kHz in one second.  
This broke the **Nyquist Limit** (which is half the sample rate, or 22,050 Hz). When you go past that limit, the audio doesn't disappear, rather it "folds" back down as a lower frequency alias. The sound went up, bounced off the ceiling, and came back down as a terrifying, chaotic screeching noise. It sounded like a demon.

### **The Math Typo**

**The Mistake:** I typed sin(20 \* PI...) instead of sin(2.0 \* PI...). **The Result:** I multiplied the pitch by 10\. instead of a nice 440Hz tone, I blasted a 4400Hz shriek at full volume. Always check your decimals.

## **4. The proof (hex dump)**

After fixing the math, I ran xxd to look at the raw bytes of the file I made. It worked perfectly:  

`00000000: 5249 4646 xxxx xxxx 5741 5645 666d 7420` `RIFF....WAVEfmt`

`00000010: 1000 0000 0100 0200 44ac 0000 10b1 0200` `........D.......`

* `52 49 46 46` \= "RIFF"
* `57 41 56 45` \= "WAVE"  
* `44 AC 00 00` \= That's 44100 in hex (Little Endian)\!

## **5. How to compile & run**

If you are on Linux or WSL, here is how you build it.  
**The Command:**

```bash
gcc -o wavgen wav.c -lm
```

**Important:** You **must** add -lm at the end. This links the math library (libm). If you forget it, GCC will yell at you about "undefined reference to sin".  
**Run it:**

```bash
./wavgen
```

This creates test.wav. Open it in VLC and enjoy the pure math

---
*powered by logic, coffee, and many sleepless nights*
