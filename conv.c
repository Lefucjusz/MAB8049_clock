#include <stdio.h>
#include <stdlib.h>

int main(void)
{
	FILE* input;
	FILE* output;
	
	input = fopen("rom.bin", "rb");
	output = fopen("rom.txt", "w");
	fprintf(output, "const unsigned char PROGMEM hex[] = {");
	while(!feof(input))
	{
		fprintf(output, "0x%X, ", fgetc(input));
	}
	fprintf(output, "};");
	fclose(input);
	fclose(output);
	//system("PAUSE");
	return 0;
}
